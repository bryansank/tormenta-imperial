"""
App visual para combinar imagenes en PDF.
Abre el navegador con drag & drop, previews y reordenamiento.

Uso: python images_to_pdf.py
"""

import io
import base64
import webbrowser
import tempfile
import os
from pathlib import Path
from threading import Timer

from flask import Flask, request, jsonify, send_file

from PIL import Image

app = Flask(__name__)

SUPPORTED = {".png", ".jpg", ".jpeg", ".bmp", ".tiff", ".tif", ".webp"}

HTML = """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Imagenes a PDF</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: 'Segoe UI', system-ui, sans-serif;
    background: #0f0f1a;
    color: #e0e0f0;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  h1 {
    margin: 30px 0 5px;
    font-size: 28px;
    font-weight: 700;
    background: linear-gradient(135deg, #a78bfa, #60a5fa);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .subtitle { color: #888; font-size: 13px; margin-bottom: 20px; }

  /* Drop zone */
  #drop-zone {
    width: 90%;
    max-width: 800px;
    border: 2px dashed #444;
    border-radius: 16px;
    padding: 40px;
    text-align: center;
    transition: all 0.3s;
    cursor: pointer;
    margin-bottom: 20px;
  }
  #drop-zone.hover {
    border-color: #a78bfa;
    background: rgba(167, 139, 250, 0.08);
  }
  #drop-zone p { font-size: 16px; color: #888; pointer-events: none; }
  #drop-zone .icon { font-size: 48px; margin-bottom: 10px; pointer-events: none; }

  /* Hidden file input */
  #file-input { display: none; }

  /* Image grid */
  #image-grid {
    width: 90%;
    max-width: 800px;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    gap: 12px;
    margin-bottom: 20px;
    min-height: 0;
  }
  .img-card {
    background: #1a1a2e;
    border-radius: 10px;
    overflow: hidden;
    position: relative;
    cursor: grab;
    transition: transform 0.2s, box-shadow 0.2s;
    border: 2px solid transparent;
  }
  .img-card:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 20px rgba(167, 139, 250, 0.2);
  }
  .img-card.dragging {
    opacity: 0.4;
    transform: scale(0.95);
  }
  .img-card.drag-over {
    border-color: #a78bfa;
  }
  .img-card img {
    width: 100%;
    height: 120px;
    object-fit: cover;
    display: block;
  }
  .img-card .info {
    padding: 6px 8px;
    font-size: 11px;
    color: #aaa;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .img-card .number {
    position: absolute;
    top: 6px;
    left: 6px;
    background: rgba(0,0,0,0.7);
    color: #a78bfa;
    font-weight: 700;
    font-size: 12px;
    padding: 2px 7px;
    border-radius: 6px;
  }
  .img-card .remove {
    position: absolute;
    top: 6px;
    right: 6px;
    background: rgba(0,0,0,0.7);
    color: #f87171;
    border: none;
    font-size: 16px;
    cursor: pointer;
    width: 24px;
    height: 24px;
    border-radius: 6px;
    display: flex;
    align-items: center;
    justify-content: center;
    opacity: 0;
    transition: opacity 0.2s;
  }
  .img-card:hover .remove { opacity: 1; }
  .img-card .remove:hover { background: #f87171; color: #fff; }

  /* Bottom bar */
  #bottom-bar {
    position: fixed;
    bottom: 0;
    width: 100%;
    background: #1a1a2e;
    border-top: 1px solid #2a2a3e;
    padding: 12px 20px;
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 15px;
    z-index: 10;
  }
  #bottom-bar .count {
    color: #888;
    font-size: 14px;
  }
  #btn-generate {
    background: linear-gradient(135deg, #a78bfa, #60a5fa);
    color: #fff;
    border: none;
    padding: 10px 30px;
    border-radius: 10px;
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
    transition: transform 0.15s, box-shadow 0.15s;
  }
  #btn-generate:hover {
    transform: translateY(-1px);
    box-shadow: 0 4px 15px rgba(167, 139, 250, 0.4);
  }
  #btn-generate:disabled {
    opacity: 0.4;
    cursor: not-allowed;
    transform: none;
    box-shadow: none;
  }
  #btn-clear {
    background: transparent;
    color: #888;
    border: 1px solid #333;
    padding: 10px 20px;
    border-radius: 10px;
    font-size: 14px;
    cursor: pointer;
    transition: border-color 0.2s;
  }
  #btn-clear:hover { border-color: #f87171; color: #f87171; }

  /* Spacer for fixed bottom bar */
  .spacer { height: 80px; }

  /* Loading overlay */
  #loading {
    display: none;
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.7);
    z-index: 100;
    justify-content: center;
    align-items: center;
    font-size: 18px;
  }
  #loading.show { display: flex; }
  .spinner {
    width: 40px; height: 40px;
    border: 3px solid #333;
    border-top-color: #a78bfa;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
    margin-right: 15px;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
</head>
<body>

<h1>Imagenes a PDF</h1>
<p class="subtitle">Arrastra imagenes o haz clic para agregar</p>

<div id="drop-zone">
  <div class="icon">&#128444;</div>
  <p>Suelta las imagenes aqui o haz clic para buscar</p>
</div>

<input type="file" id="file-input" multiple accept="image/*">

<div id="image-grid"></div>

<div class="spacer"></div>

<div id="bottom-bar">
  <span class="count" id="count">0 imagenes</span>
  <button id="btn-clear" onclick="clearAll()">Limpiar</button>
  <button id="btn-generate" onclick="generate()" disabled>Generar PDF</button>
</div>

<div id="loading">
  <div class="spinner"></div>
  <span>Generando PDF...</span>
</div>

<script>
const images = []; // { file, dataUrl, name }
let dragIdx = null;

const dropZone = document.getElementById('drop-zone');
const fileInput = document.getElementById('file-input');
const grid = document.getElementById('image-grid');
const countEl = document.getElementById('count');
const btnGen = document.getElementById('btn-generate');
const loading = document.getElementById('loading');

// Drop zone events
dropZone.addEventListener('click', () => fileInput.click());
dropZone.addEventListener('dragover', e => { e.preventDefault(); dropZone.classList.add('hover'); });
dropZone.addEventListener('dragleave', () => dropZone.classList.remove('hover'));
dropZone.addEventListener('drop', e => {
  e.preventDefault();
  dropZone.classList.remove('hover');
  addFiles(e.dataTransfer.files);
});

fileInput.addEventListener('change', () => {
  addFiles(fileInput.files);
  fileInput.value = '';
});

function addFiles(fileList) {
  for (const f of fileList) {
    if (!f.type.startsWith('image/')) continue;
    const reader = new FileReader();
    reader.onload = ev => {
      images.push({ file: f, dataUrl: ev.target.result, name: f.name });
      render();
    };
    reader.readAsDataURL(f);
  }
}

function render() {
  grid.innerHTML = '';
  images.forEach((img, i) => {
    const card = document.createElement('div');
    card.className = 'img-card';
    card.draggable = true;
    card.innerHTML = `
      <span class="number">${i + 1}</span>
      <button class="remove" onclick="removeImg(${i})">&times;</button>
      <img src="${img.dataUrl}" alt="${img.name}">
      <div class="info">${img.name}</div>
    `;

    card.addEventListener('dragstart', () => { dragIdx = i; card.classList.add('dragging'); });
    card.addEventListener('dragend', () => { dragIdx = null; card.classList.remove('dragging'); });
    card.addEventListener('dragover', e => { e.preventDefault(); card.classList.add('drag-over'); });
    card.addEventListener('dragleave', () => card.classList.remove('drag-over'));
    card.addEventListener('drop', e => {
      e.preventDefault();
      card.classList.remove('drag-over');
      if (dragIdx !== null && dragIdx !== i) {
        const item = images.splice(dragIdx, 1)[0];
        images.splice(i, 0, item);
        render();
      }
    });

    grid.appendChild(card);
  });
  countEl.textContent = `${images.length} imagen${images.length !== 1 ? 'es' : ''}`;
  btnGen.disabled = images.length === 0;
}

function removeImg(i) {
  images.splice(i, 1);
  render();
}

function clearAll() {
  images.length = 0;
  render();
}

async function generate() {
  if (images.length === 0) return;
  loading.classList.add('show');

  const formData = new FormData();
  images.forEach((img, i) => {
    formData.append('images', img.file, `${String(i).padStart(4, '0')}_${img.name}`);
  });

  try {
    const resp = await fetch('/generate', { method: 'POST', body: formData });
    if (!resp.ok) throw new Error(await resp.text());

    const blob = await resp.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'imagenes.pdf';
    a.click();
    URL.revokeObjectURL(url);
  } catch (err) {
    alert('Error: ' + err.message);
  } finally {
    loading.classList.remove('show');
  }
}
</script>
</body>
</html>"""


@app.route("/")
def index():
    return HTML


@app.route("/generate", methods=["POST"])
def generate():
    files = request.files.getlist("images")
    if not files:
        return "No images received", 400

    pil_images = []
    for f in sorted(files, key=lambda x: x.filename):
        img = Image.open(f.stream)
        if img.mode in ("RGBA", "LA", "P"):
            img = img.convert("RGB")
        pil_images.append(img)

    buf = io.BytesIO()
    first, *rest = pil_images
    first.save(buf, "PDF", save_all=True, append_images=rest)
    buf.seek(0)

    return send_file(buf, mimetype="application/pdf", download_name="imagenes.pdf")


def main():
    port = 5050
    print(f"\n  Abriendo en http://localhost:{port}\n")
    Timer(1, lambda: webbrowser.open(f"http://localhost:{port}")).start()
    app.run(port=port, debug=False)


if __name__ == "__main__":
    main()
