"""Экспорт SigLIP 2 (google/siglip2-base-patch16-224, Apache-2.0) в Core ML для подписей вещей.

Выход (в --out):
  SigLIP2Image.mlpackage   — image-энкодер: картинка 224×224 → нормированный вектор 768
  labels.json              — список подписей (русские названия + сколько прототипов)
  label_embeddings.bin     — float32 [N, 768], нормированные текстовые эмбеддинги подписей
  meta.json                — logit_scale / logit_bias для оценки уверенности (sigmoid)

Запуск: python export_siglip2.py --out build  (нужны torch, transformers, coremltools)
"""
import argparse, json, pathlib, struct
import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

MODEL = "google/siglip2-base-patch16-224"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build")
    ap.add_argument("--labels", default="labels_ru.txt")
    ap.add_argument("--no-coreml", action="store_true")
    args = ap.parse_args()
    out = pathlib.Path(args.out); out.mkdir(parents=True, exist_ok=True)

    model = AutoModel.from_pretrained(MODEL, torch_dtype=torch.float32).eval()
    tok = AutoTokenizer.from_pretrained(MODEL)

    # ---------- текстовые эмбеддинги подписей ----------
    labels = []
    for line in pathlib.Path(args.labels).read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"): continue
        # «Кружка | mug, cup» — русское имя и синонимы-подсказки через запятую
        name, _, syn = line.partition("|")
        prompts = [name.strip()] + [s.strip() for s in syn.split(",") if s.strip()]
        labels.append((name.strip(), prompts))

    templates = ["{}", "фото: {}", "на фото {}", "предмет: {}"]
    embs = []
    with torch.no_grad():
        for name, prompts in labels:
            texts = [t.format(p) for p in prompts for t in templates]
            enc = tok(texts, padding="max_length", max_length=64, truncation=True, return_tensors="pt")
            e = model.get_text_features(**enc)
            e = e / e.norm(dim=-1, keepdim=True)
            m = e.mean(dim=0); m = m / m.norm()
            embs.append(m.numpy().astype(np.float32))
    E = np.stack(embs)
    (out / "label_embeddings.bin").write_bytes(E.tobytes())
    (out / "labels.json").write_text(json.dumps({"labels": [n for n, _ in labels], "dim": int(E.shape[1])}, ensure_ascii=False, indent=0), encoding="utf-8")
    (out / "meta.json").write_text(json.dumps({
        "model": MODEL,
        "logit_scale": float(model.logit_scale.exp().item()),
        "logit_bias": float(model.logit_bias.item()),
        "image_size": 224,
    }, indent=2))
    print(f"labels: {len(labels)}, dim {E.shape[1]}")

    if args.no_coreml: return

    # ---------- image-энкодер → Core ML ----------
    import coremltools as ct

    class ImageEncoder(torch.nn.Module):
        def __init__(self, m): super().__init__(); self.m = m
        def forward(self, pixel_values):
            e = self.m.get_image_features(pixel_values=pixel_values)
            return e / e.norm(dim=-1, keepdim=True)

    enc = ImageEncoder(model).eval()
    example = torch.rand(1, 3, 224, 224) * 2 - 1
    traced = torch.jit.trace(enc, example)
    # SigLIP нормализует пиксели как (x/255 - 0.5)/0.5 = x/127.5 - 1
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=(1, 3, 224, 224), scale=1 / 127.5, bias=[-1, -1, -1], color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )
    mlmodel.short_description = "SigLIP 2 base/16 image encoder (Apache-2.0) — вектор вещи для подписи"
    try:
        from coremltools.optimize.coreml import OpPalettizerConfig, OptimizationConfig, palettize_weights
        cfg = OptimizationConfig(global_config=OpPalettizerConfig(mode="kmeans", nbits=6, granularity="per_grouped_channel", group_size=16))
        mlmodel = palettize_weights(mlmodel, cfg)
        print("palettized 6-bit")
    except Exception as e:
        print("palettization skipped:", e)
    mlmodel.save(str(out / "SigLIP2Image.mlpackage"))
    print("saved", out / "SigLIP2Image.mlpackage")

if __name__ == "__main__":
    main()
