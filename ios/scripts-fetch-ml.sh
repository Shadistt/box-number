#!/bin/sh
# Скачивает Core ML модель подписей (SigLIP 2) из релиза GitHub в ios/BoxNo/ML/. Нужен gh с доступом к репозиторию.
set -e
cd "$(dirname "$0")"
mkdir -p BoxNo/ML
gh release download ml-v1 --repo Shadistt/box-number --pattern SigLIP2Image.mlpackage.zip --dir /tmp --clobber
rm -rf BoxNo/ML/SigLIP2Image.mlpackage
unzip -q -o /tmp/SigLIP2Image.mlpackage.zip -d BoxNo/ML/
echo "ok: BoxNo/ML/SigLIP2Image.mlpackage"
