"""
Generate app icon with black background using existing PNG icon.
Requires: pip install Pillow
Usage: python generate_black_icon.py
"""
from PIL import Image
import os, shutil

ICON_SIZE = 1024
LOGO_SCALE = 0.55
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ICON_PATH = os.path.join(SCRIPT_DIR, 'assets', 'icon_with_bg.png')
BACKUP_PATH = os.path.join(SCRIPT_DIR, 'assets', 'icon_with_bg_old.png')

def main():
    if not os.path.exists(ICON_PATH):
        print(f'Icon not found at {ICON_PATH}')
        return

    # Backup original
    if not os.path.exists(BACKUP_PATH):
        shutil.copy2(ICON_PATH, BACKUP_PATH)
        print(f'Backed up original to {BACKUP_PATH}')

    # Load original icon (has the logo with old background)
    original = Image.open(BACKUP_PATH).convert('RGBA')

    # Resize logo smaller
    logo_size = int(ICON_SIZE * LOGO_SCALE)
    logo = original.resize((logo_size, logo_size), Image.LANCZOS)

    # Create black background
    img = Image.new('RGBA', (ICON_SIZE, ICON_SIZE), (0, 0, 0, 255))

    # Center the logo
    x = (ICON_SIZE - logo_size) // 2
    y = (ICON_SIZE - logo_size) // 2
    img.paste(logo, (x, y), logo)

    # Convert to RGB (no alpha) for app icon
    final = Image.new('RGB', (ICON_SIZE, ICON_SIZE), (0, 0, 0))
    final.paste(img, mask=img.split()[3])
    final.save(ICON_PATH, 'PNG')
    print(f'New icon saved: {ICON_SIZE}x{ICON_SIZE}, logo {logo_size}x{logo_size}')
    print('\nNext: cd stocker && flutter pub run flutter_launcher_icons')

if __name__ == '__main__':
    main()
