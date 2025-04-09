from PIL import Image
import os

def generate_favicon():
    # Abrimos la imagen del logo
    logo_path = 'static/img/ateca-techlab-new-logo.png'
    if not os.path.exists(logo_path):
        print(f"Error: No se pudo encontrar el archivo {logo_path}")
        return
    
    try:
        # Abrimos la imagen
        img = Image.open(logo_path)
        
        # Redimensionamos a tamaño de favicon (32x32 píxeles)
        favicon_size = (32, 32)
        favicon = img.resize(favicon_size)
        
        # Guardamos como ICO
        favicon.save('static/img/favicon.ico')
        
        # Guardamos también en tamaños más grandes para diferentes dispositivos
        sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128)]
        for size in sizes:
            resized = img.resize(size)
            resized.save(f'static/img/favicon-{size[0]}x{size[1]}.png')
        
        print("Favicon generado con éxito")
    except Exception as e:
        print(f"Error al generar el favicon: {e}")

if __name__ == "__main__":
    generate_favicon()