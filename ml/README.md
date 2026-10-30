# ML · подписи вещей

- `export_siglip2.py` — экспорт `google/siglip2-base-patch16-224` (Apache-2.0) в Core ML + текстовые эмбеддинги подписей.
- `labels_ru.txt` — список подписей по-русски («Название | синонимы»). Правите список → запускаете экспорт → обновляете `ios/BoxNo/ML/labels.json` и `label_embeddings.bin` (модель перегонять не нужно).
- Модель `SigLIP2Image.mlpackage` (67 МБ, 6-bit) лежит в релизе GitHub `ml-v1`, в git не хранится.

```
python -m venv venv && . venv/bin/activate
pip install --index-url https://download.pytorch.org/whl/cpu torch
pip install coremltools transformers sentencepiece pillow numpy
python export_siglip2.py --out build
```

Почему не MobileCLIP: веса Apple выпущены под research-only лицензией — в продукте использовать нельзя.
