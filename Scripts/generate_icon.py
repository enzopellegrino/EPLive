#!/usr/bin/env python3
"""
Genera l'icona per EPLive - App di streaming live
Design: Cerchio rosso "LIVE" con simbolo play/broadcast
"""

import os
import subprocess
from pathlib import Path

def create_icon_svg():
    """Crea l'SVG dell'icona EPLive"""
    svg = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <!-- Gradiente sfondo -->
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1a1a2e"/>
      <stop offset="50%" style="stop-color:#16213e"/>
      <stop offset="100%" style="stop-color:#0f0f23"/>
    </linearGradient>
    
    <!-- Gradiente rosso per LIVE -->
    <linearGradient id="redGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#ff4757"/>
      <stop offset="100%" style="stop-color:#ff2d2d"/>
    </linearGradient>
    
    <!-- Glow effect -->
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="15" result="coloredBlur"/>
      <feMerge>
        <feMergeNode in="coloredBlur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
    
    <!-- Shadow -->
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="8" stdDeviation="20" flood-color="#000" flood-opacity="0.5"/>
    </filter>
  </defs>
  
  <!-- Background con angoli arrotondati (stile iOS) -->
  <rect width="1024" height="1024" rx="224" ry="224" fill="url(#bgGrad)"/>
  
  <!-- Onde di trasmissione esterne -->
  <g opacity="0.3" stroke="#ff4757" stroke-width="8" fill="none">
    <path d="M 720 512 A 208 208 0 0 1 720 512" transform="rotate(-30 512 512)">
      <animate attributeName="d" 
               values="M 720 512 A 208 208 0 0 1 512 720;M 780 512 A 268 268 0 0 1 512 780;M 720 512 A 208 208 0 0 1 512 720"
               dur="2s" repeatCount="indefinite"/>
    </path>
  </g>
  
  <!-- Cerchio esterno decorativo -->
  <circle cx="512" cy="512" r="380" fill="none" stroke="#ffffff" stroke-width="3" opacity="0.1"/>
  
  <!-- Cerchio principale con glow -->
  <circle cx="512" cy="512" r="280" fill="url(#redGrad)" filter="url(#shadow)"/>
  
  <!-- Inner highlight -->
  <circle cx="512" cy="480" r="260" fill="none" stroke="#ffffff" stroke-width="2" opacity="0.2"/>
  
  <!-- Simbolo Play (triangolo) -->
  <path d="M 450 380 L 620 512 L 450 644 Z" fill="#ffffff" filter="url(#glow)"/>
  
  <!-- Testo EP piccolo in alto -->
  <text x="512" y="280" font-family="SF Pro Display, Helvetica Neue, Arial" font-size="72" font-weight="bold" 
        fill="#ffffff" text-anchor="middle" opacity="0.9">EP</text>
  
  <!-- Testo LIVE in basso -->
  <text x="512" y="820" font-family="SF Pro Display, Helvetica Neue, Arial" font-size="100" font-weight="900" 
        fill="url(#redGrad)" text-anchor="middle" letter-spacing="8">LIVE</text>
  
  <!-- Dot pulsante accanto a LIVE -->
  <circle cx="340" cy="795" r="20" fill="#ff4757">
    <animate attributeName="opacity" values="1;0.3;1" dur="1.5s" repeatCount="indefinite"/>
  </circle>
</svg>'''
    return svg


def create_simple_icon_svg():
    """Versione semplificata per rendering migliore a piccole dimensioni"""
    svg = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1a1a2e"/>
      <stop offset="100%" style="stop-color:#0f0f23"/>
    </linearGradient>
    <linearGradient id="redGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#ff4757"/>
      <stop offset="100%" style="stop-color:#e63946"/>
    </linearGradient>
  </defs>
  
  <!-- Background -->
  <rect width="1024" height="1024" rx="224" ry="224" fill="url(#bgGrad)"/>
  
  <!-- Cerchio rosso centrale -->
  <circle cx="512" cy="460" r="300" fill="url(#redGrad)"/>
  
  <!-- Simbolo Play bianco -->
  <path d="M 440 320 L 640 460 L 440 600 Z" fill="#ffffff"/>
  
  <!-- Testo LIVE -->
  <text x="512" y="850" font-family="Helvetica Neue, Arial, sans-serif" font-size="140" font-weight="900" 
        fill="#ffffff" text-anchor="middle" letter-spacing="12">LIVE</text>
  
  <!-- Dot rosso -->
  <circle cx="270" cy="815" r="28" fill="#ff4757"/>
</svg>'''
    return svg


def main():
    script_dir = Path(__file__).parent
    project_dir = script_dir.parent
    assets_dir = project_dir / "EPLive" / "Assets.xcassets" / "AppIcon.appiconset"
    
    # Crea directory se non esiste
    assets_dir.mkdir(parents=True, exist_ok=True)
    
    # Salva SVG
    svg_path = script_dir / "EPLive_Icon.svg"
    svg_content = create_simple_icon_svg()
    
    with open(svg_path, 'w') as f:
        f.write(svg_content)
    
    print(f"✅ SVG creato: {svg_path}")
    
    # Dimensioni richieste per iOS e macOS
    sizes = [
        # iOS
        (20, 1), (20, 2), (20, 3),
        (29, 1), (29, 2), (29, 3),
        (40, 1), (40, 2), (40, 3),
        (60, 2), (60, 3),
        (76, 1), (76, 2),
        (83.5, 2),
        # App Store
        (1024, 1),
        # macOS
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2),
    ]
    
    # Genera PNG usando sips (macOS built-in)
    print("\n🎨 Generazione icone PNG...")
    
    # Prima converti SVG in PNG 1024x1024 usando qlmanage o rsvg-convert
    master_png = script_dir / "EPLive_Icon_1024.png"
    
    # Prova con rsvg-convert (più affidabile per SVG)
    try:
        subprocess.run([
            "rsvg-convert", "-w", "1024", "-h", "1024",
            str(svg_path), "-o", str(master_png)
        ], check=True, capture_output=True)
        print(f"✅ PNG master creato con rsvg-convert")
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Fallback: usa qlmanage
        try:
            subprocess.run([
                "qlmanage", "-t", "-s", "1024", "-o", str(script_dir), str(svg_path)
            ], check=True, capture_output=True)
            # qlmanage aggiunge .png al nome
            temp_png = script_dir / "EPLive_Icon.svg.png"
            if temp_png.exists():
                temp_png.rename(master_png)
            print(f"✅ PNG master creato con qlmanage")
        except:
            print("⚠️  Installa librsvg per convertire SVG:")
            print("    brew install librsvg")
            print(f"\n📁 SVG salvato in: {svg_path}")
            print("   Puoi convertirlo manualmente o usare un tool online")
            create_contents_json(assets_dir)
            return
    
    if not master_png.exists():
        print("❌ Errore nella creazione del PNG master")
        return
    
    # Genera tutte le dimensioni
    generated = set()
    for base_size, scale in sizes:
        pixel_size = int(base_size * scale)
        if pixel_size in generated:
            continue
        generated.add(pixel_size)
        
        output_name = f"icon_{pixel_size}x{pixel_size}.png"
        output_path = assets_dir / output_name
        
        subprocess.run([
            "sips", "-z", str(pixel_size), str(pixel_size),
            str(master_png), "--out", str(output_path)
        ], capture_output=True)
        print(f"  📱 {output_name}")
    
    # Crea Contents.json
    create_contents_json(assets_dir)
    
    print(f"\n✅ Icone generate in: {assets_dir}")
    print("\n🔧 Apri Xcode e verifica le icone in Assets.xcassets")


def create_contents_json(assets_dir):
    """Crea il Contents.json per le icone"""
    contents = '''{
  "images" : [
    {
      "filename" : "icon_40x40.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "20x20"
    },
    {
      "filename" : "icon_60x60.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "29x29"
    },
    {
      "filename" : "icon_80x80.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "38x38"
    },
    {
      "filename" : "icon_80x80.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "40x40"
    },
    {
      "filename" : "icon_120x120.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "60x60"
    },
    {
      "filename" : "icon_136x136.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "64x64"
    },
    {
      "filename" : "icon_152x152.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "68x68"
    },
    {
      "filename" : "icon_160x160.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "76x76"
    },
    {
      "filename" : "icon_167x167.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "83.5x83.5"
    },
    {
      "filename" : "icon_1024x1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_64x64.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_1024x1024.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}'''
    
    with open(assets_dir / "Contents.json", 'w') as f:
        f.write(contents)
    print("✅ Contents.json aggiornato")


if __name__ == "__main__":
    main()
