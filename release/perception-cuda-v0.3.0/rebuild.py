#!/usr/bin/env python3
"""Reconstruct pinned CUDA perception build inputs in a NEW directory; never push."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import urllib.request

BUNDLE=Path(__file__).resolve().parent

def call(command):
    subprocess.run(command,check=True)

def clone(url,sha,path):
    if not url.startswith('https://github.com/') or len(sha)!=40 or any(c not in '0123456789abcdef' for c in sha):
        raise ValueError('Expected HTTPS GitHub URL and full pinned commit')
    path.mkdir(parents=True,exist_ok=False)
    call(['git','init','-q',str(path)])
    call(['git','-C',str(path),'remote','add','origin',url])
    call(['git','-C',str(path),'fetch','--depth','1','origin',sha])
    call(['git','-C',str(path),'checkout','--detach',sha])

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace',type=Path,required=True,help='New build directory on a disk with sufficient free space')
    parser.add_argument('--arch',choices=['amd64','arm64'],required=True)
    parser.add_argument('--builder',required=True,help='Existing Docker buildx builder; native target preferred')
    parser.add_argument('--prepare-only',action='store_true')
    args=parser.parse_args()
    root=args.workspace.resolve()
    if root.exists():raise SystemExit('Refusing to overwrite an existing workspace; use a new directory')
    lock=json.loads((BUNDLE/'gpu-build/sources.lock.json').read_text())
    clone('https://github.com/OSS-TEST-GROUP/katech-autoware.git',lock['top_commit'],root)
    for name,row in lock['repositories'].items():
        rel=Path(name)
        if rel.is_absolute() or '..' in rel.parts:raise ValueError('Unsafe repository path')
        clone(row['url'],row['version'],root/'src'/rel)
    shutil.copytree(BUNDLE/'gpu-build',root/'gpu-build')
    models=root/'gpu-build/models'
    manifest=json.loads((models/'manifest.json').read_text())
    for item in manifest['files']:
        name=item['file']
        if Path(name).name!=name:raise ValueError('Unsafe model path')
        if not item['url'].startswith('https://github.com/OSS-TEST-GROUP/katech-autoware-sils/releases/download/'):
            raise ValueError('Unexpected model origin')
        req=urllib.request.Request(item['url'],headers={'User-Agent':'katech-perception-rebuild'})
        with urllib.request.urlopen(req,timeout=120) as response:
            data=response.read(item['bytes']+1)
        if len(data)!=item['bytes'] or hashlib.sha256(data).hexdigest()!=item['sha256']:
            raise ValueError('Model size/hash mismatch: '+name)
        (models/name).write_bytes(data)
    recipe=root/'gpu-build'/('Dockerfile.arm64' if args.arch=='arm64' else 'Dockerfile')
    cmd=['docker','buildx','build','--builder',args.builder,'--platform','linux/'+args.arch,
         '--progress','plain','--build-arg','ROS_DISTRO=humble','--build-arg',
         'LIB_DIR='+('aarch64' if args.arch=='arm64' else 'x86_64'),
         '--build-arg','OCI_REVISION='+lock['top_commit'],
         '--build-arg','OCI_VERSION=0.3.0-candidate','--provenance=false','-f',str(recipe)]
    print('Sources/models prepared:',root,flush=True)
    if args.prepare_only:
        print('Preparation only; no image built. Use gpu-build/Dockerfile[.arm64] from this context.')
        return
    call(cmd+['--target','adsw-perception-depend',str(root)])
    call(cmd+['--target','trained-perception','--load','-t',
              'katech-perception-local:v0.3.0-candidate-'+args.arch+'-cuda',str(root)])

if __name__=='__main__':main()
