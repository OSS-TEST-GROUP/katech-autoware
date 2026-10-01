#!/usr/bin/env python3
"""Add every CARLA Town01 traffic light to a Lanelet2 map.

The generated IDs are based on stable OpenDRIVE signal IDs, not CARLA actor
IDs (which change every time the world is restarted). Run this script while a
Town01 CARLA server is active and write the result to a new file first.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
import xml.etree.ElementTree as ET


GENERATED_ID_MIN = 900_000_000
GENERATED_ID_MAX = 901_000_000
TRAFFIC_LIGHT_TYPE = "1000001"


def tags(element: ET.Element) -> dict[str, str]:
    return {tag.attrib["k"]: tag.attrib["v"] for tag in element.findall("tag")}


def generated_id(signal_id: int, suffix: int) -> int:
    value = int(f"900{signal_id:03d}{suffix:03d}")
    if not GENERATED_ID_MIN <= value < GENERATED_ID_MAX:
        raise ValueError(f"unsupported OpenDRIVE signal ID: {signal_id}")
    return value


def distance_to_segment(
    point: tuple[float, float], start: tuple[float, float], end: tuple[float, float]
) -> float:
    px, py = point
    ax, ay = start
    bx, by = end
    dx, dy = bx - ax, by - ay
    length_sq = dx * dx + dy * dy
    if length_sq == 0.0:
        return math.hypot(px - ax, py - ay)
    ratio = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length_sq))
    return math.hypot(px - (ax + ratio * dx), py - (ay + ratio * dy))


def point_in_polygon(point: tuple[float, float], polygon: list[tuple[float, float]]) -> bool:
    inside = False
    px, py = point
    previous = polygon[-1]
    for current in polygon:
        ax, ay = previous
        bx, by = current
        if distance_to_segment(point, previous, current) < 1.0e-6:
            return True
        if (ay > py) != (by > py):
            intersection_x = (bx - ax) * (py - ay) / (by - ay) + ax
            if px < intersection_x:
                inside = not inside
        previous = current
    return inside


def polygon_distance(point: tuple[float, float], polygon: list[tuple[float, float]]) -> float:
    if point_in_polygon(point, polygon):
        return 0.0
    return min(
        distance_to_segment(point, polygon[index - 1], polygon[index])
        for index in range(len(polygon))
    )


def nearest_unused(source, candidates, used: set[int], location_getter, max_distance: float):
    source_location = location_getter(source)
    choices = []
    for index, candidate in enumerate(candidates):
        if index in used:
            continue
        candidate_location = location_getter(candidate)
        distance = math.hypot(
            source_location.x - candidate_location.x,
            source_location.y - candidate_location.y,
        )
        choices.append((distance, index, candidate))
    distance, index, candidate = min(choices, key=lambda item: item[0])
    if distance > max_distance:
        raise RuntimeError(f"nearest CARLA object is {distance:.3f} m away")
    used.add(index)
    return candidate


def add_tag(element: ET.Element, key: str, value: str) -> None:
    ET.SubElement(element, "tag", {"k": key, "v": value})


def make_node(node_id: int, x: float, y: float, z: float) -> ET.Element:
    node = ET.Element(
        "node",
        {"id": str(node_id), "visible": "true", "version": "1", "lat": "0", "lon": "0"},
    )
    add_tag(node, "ele", f"{z:.6f}")
    add_tag(node, "local_x", f"{x:.6f}")
    add_tag(node, "local_y", f"{y:.6f}")
    return node


def make_way(way_id: int, node_ids: tuple[int, int], way_type: str) -> ET.Element:
    way = ET.Element("way", {"id": str(way_id), "visible": "true", "version": "1"})
    for node_id in node_ids:
        ET.SubElement(way, "nd", {"ref": str(node_id)})
    add_tag(way, "type", way_type)
    if way_type == "traffic_light":
        add_tag(way, "subtype", "red_yellow_green")
    else:
        add_tag(way, "subtype", "solid")
    return way


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=2000, type=int)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    import carla

    client = carla.Client(args.host, args.port)
    client.set_timeout(10.0)
    world = client.get_world()
    world.wait_for_tick(5.0)
    carla_map = world.get_map()
    if not carla_map.name.endswith("/Town01"):
        raise RuntimeError(f"expected Town01, got {carla_map.name}")

    landmarks_by_id = {}
    for landmark in carla_map.get_all_landmarks():
        if landmark.type == TRAFFIC_LIGHT_TYPE:
            landmarks_by_id.setdefault(int(landmark.id), landmark)
    landmarks = [landmarks_by_id[key] for key in sorted(landmarks_by_id)]
    actors = sorted(world.get_actors().filter("traffic.traffic_light*"), key=lambda actor: actor.id)
    bounding_boxes = list(world.get_level_bbs(carla.CityObjectLabel.TrafficLight))
    if not (len(landmarks) == len(actors) == len(bounding_boxes) == 36):
        raise RuntimeError(
            f"expected 36 lights, got landmarks={len(landmarks)}, "
            f"actors={len(actors)}, bounding_boxes={len(bounding_boxes)}"
        )

    actor_used: set[int] = set()
    bbox_used: set[int] = set()
    runtime = []
    for landmark in landmarks:
        actor = nearest_unused(
            landmark,
            actors,
            actor_used,
            lambda item: item.transform.location if hasattr(item, "transform") else item.get_location(),
            1.0,
        )
        bbox = nearest_unused(
            landmark,
            bounding_boxes,
            bbox_used,
            lambda item: item.transform.location if hasattr(item, "transform") else item.location,
            1.0,
        )
        stop_waypoints = actor.get_stop_waypoints()
        if len(stop_waypoints) != 1:
            raise RuntimeError(
                f"signal {landmark.id} actor {actor.id} has {len(stop_waypoints)} stop waypoints"
            )
        runtime.append((int(landmark.id), landmark, actor, bbox, stop_waypoints[0]))

    tree = ET.parse(args.input)
    root = tree.getroot()

    for element in list(root):
        element_id = int(element.attrib.get("id", "-1"))
        if GENERATED_ID_MIN <= element_id < GENERATED_ID_MAX:
            root.remove(element)
    for relation in root.findall("relation"):
        for member in list(relation.findall("member")):
            reference = int(member.attrib.get("ref", "-1"))
            if member.attrib.get("role") == "regulatory_element" and (
                GENERATED_ID_MIN <= reference < GENERATED_ID_MAX
            ):
                relation.remove(member)

    node_coordinates = {}
    for node in root.findall("node"):
        node_tags = tags(node)
        if "local_x" in node_tags and "local_y" in node_tags:
            node_coordinates[int(node.attrib["id"])] = (
                float(node_tags["local_x"]),
                float(node_tags["local_y"]),
            )
    ways = {
        int(way.attrib["id"]): [int(item.attrib["ref"]) for item in way.findall("nd")]
        for way in root.findall("way")
    }
    lanelets = []
    for relation in root.findall("relation"):
        relation_tags = tags(relation)
        if relation_tags.get("type") != "lanelet" or relation_tags.get("subtype") != "road":
            continue
        members = {member.attrib.get("role"): member for member in relation.findall("member")}
        if "left" not in members or "right" not in members:
            continue
        left = [node_coordinates[item] for item in ways[int(members["left"].attrib["ref"])]]
        right = [node_coordinates[item] for item in ways[int(members["right"].attrib["ref"])]]
        polygon = left + list(reversed(right))
        start = ((left[0][0] + right[0][0]) / 2.0, (left[0][1] + right[0][1]) / 2.0)
        end = ((left[-1][0] + right[-1][0]) / 2.0, (left[-1][1] + right[-1][1]) / 2.0)
        length = math.hypot(end[0] - start[0], end[1] - start[1])
        if length > 0.0:
            direction = ((end[0] - start[0]) / length, (end[1] - start[1]) / length)
            lanelets.append((relation, polygon, direction))

    generated_nodes = []
    generated_ways = []
    generated_relations = []
    assignments = []
    for signal_id, landmark, actor, bbox, stop_waypoint in runtime:
        stop_location = stop_waypoint.transform.location
        stop_point = (stop_location.x, -stop_location.y)
        yaw = math.radians(stop_waypoint.transform.rotation.yaw)
        forward = (math.cos(yaw), -math.sin(yaw))
        candidates = []
        for relation, polygon, direction in lanelets:
            distance = polygon_distance(stop_point, polygon)
            alignment = forward[0] * direction[0] + forward[1] * direction[1]
            if distance <= 1.0 and alignment > 0.5:
                candidates.append((distance, -alignment, int(relation.attrib["id"]), relation))
        if not candidates:
            raise RuntimeError(f"no lanelet found for signal {signal_id} at {stop_point}")
        _, _, lanelet_id, lanelet_relation = min(candidates, key=lambda item: item[:3])

        signal_node_1 = generated_id(signal_id, 1)
        signal_node_2 = generated_id(signal_id, 2)
        stop_node_1 = generated_id(signal_id, 3)
        stop_node_2 = generated_id(signal_id, 4)
        signal_way_id = generated_id(signal_id, 10)
        stop_way_id = generated_id(signal_id, 11)
        regulatory_id = generated_id(signal_id, 20)

        signal_yaw = math.radians(landmark.transform.rotation.yaw + 90.0)
        signal_dx = math.cos(signal_yaw) * landmark.width / 2.0
        signal_dy = math.sin(signal_yaw) * landmark.width / 2.0
        signal_bottom = bbox.location.z - bbox.extent.z
        generated_nodes.extend(
            [
                make_node(
                    signal_node_1,
                    bbox.location.x - signal_dx,
                    -(bbox.location.y - signal_dy),
                    signal_bottom,
                ),
                make_node(
                    signal_node_2,
                    bbox.location.x + signal_dx,
                    -(bbox.location.y + signal_dy),
                    signal_bottom,
                ),
            ]
        )

        stop_yaw = math.radians(stop_waypoint.transform.rotation.yaw + 90.0)
        stop_dx = math.cos(stop_yaw) * stop_waypoint.lane_width / 2.0
        stop_dy = math.sin(stop_yaw) * stop_waypoint.lane_width / 2.0
        generated_nodes.extend(
            [
                make_node(
                    stop_node_1,
                    stop_location.x - stop_dx,
                    -(stop_location.y - stop_dy),
                    stop_location.z,
                ),
                make_node(
                    stop_node_2,
                    stop_location.x + stop_dx,
                    -(stop_location.y + stop_dy),
                    stop_location.z,
                ),
            ]
        )

        signal_way = make_way(signal_way_id, (signal_node_1, signal_node_2), "traffic_light")
        add_tag(signal_way, "height", f"{2.0 * bbox.extent.z:.6f}")
        stop_way = make_way(stop_way_id, (stop_node_1, stop_node_2), "stop_line")
        generated_ways.extend([signal_way, stop_way])

        regulatory = ET.Element(
            "relation", {"id": str(regulatory_id), "visible": "true", "version": "1"}
        )
        ET.SubElement(
            regulatory, "member", {"type": "way", "ref": str(signal_way_id), "role": "refers"}
        )
        ET.SubElement(
            regulatory, "member", {"type": "way", "ref": str(stop_way_id), "role": "ref_line"}
        )
        add_tag(regulatory, "type", "regulatory_element")
        add_tag(regulatory, "subtype", "traffic_light")
        generated_relations.append(regulatory)

        first_tag_index = next(
            (index for index, child in enumerate(lanelet_relation) if child.tag == "tag"),
            len(lanelet_relation),
        )
        lanelet_relation.insert(
            first_tag_index,
            ET.Element(
                "member",
                {"type": "relation", "ref": str(regulatory_id), "role": "regulatory_element"},
            ),
        )
        assignments.append((signal_id, actor.id, lanelet_id, regulatory_id))

    first_way_index = next(index for index, child in enumerate(root) if child.tag == "way")
    for offset, node in enumerate(generated_nodes):
        root.insert(first_way_index + offset, node)
    first_relation_index = next(index for index, child in enumerate(root) if child.tag == "relation")
    for offset, way in enumerate(generated_ways):
        root.insert(first_relation_index + offset, way)
    root.extend(generated_relations)

    ET.indent(tree, space="  ")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    tree.write(args.output, encoding="utf-8", xml_declaration=True)
    print(f"generated {len(assignments)} traffic-light regulatory elements in {args.output}")
    for signal_id, actor_id, lanelet_id, regulatory_id in assignments:
        print(
            f"signal={signal_id} runtime_actor={actor_id} "
            f"lanelet={lanelet_id} regulatory_element={regulatory_id}"
        )


if __name__ == "__main__":
    main()
