#!/usr/bin/env python3
"""
Generate app icon PNG from SVG with white background
Requires: pip install cairosvg pillow
"""

try:
    from cairosvg import svg2png
    from PIL import Image, ImageDraw
    import io
except ImportError:
    print("❌ Missing dependencies. Please install:")
    print("   pip install cairosvg pillow")
    exit(1)

def create_icon_with_background(svg_path, output_path, size=1024, padding_percent=15):
    """Create a PNG icon with white background and padding"""
    
    # Calculate logo size with padding
    padding = int(size * padding_percent / 100)
    logo_size = size - (2 * padding)
    
    # Convert SVG to PNG at the logo size
    png_data = svg2png(
        url=svg_path,
        output_width=logo_size,
        output_height=logo_size
    )
    
    # Load the logo
    logo = Image.open(io.BytesIO(png_data))
    
    # Create white background
    background = Image.new('RGB', (size, size), 'white')
    
    # If logo has transparency, composite it
    if logo.mode == 'RGBA':
        background.paste(logo, (padding, padding), logo)
    else:
        background.paste(logo, (padding, padding))
    
    # Save the result
    background.save(output_path, 'PNG', quality=100)
    print(f"✅ Created {output_path} ({size}x{size})")

def generate_all_sizes():
    """Generate icons for all required sizes"""
    svg_path = 'assets/Subtract.svg'
    
    # Main icon for flutter_launcher_icons
    create_icon_with_background(svg_path, 'assets/icon_with_bg.png', 1024, 12)
    
    # Android sizes
    android_sizes = {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192
    }
    
    print("\n📱 Android icons:")
    for density, size in android_sizes.items():
        output = f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'
        create_icon_with_background(svg_path, output, size, 12)
    
    # iOS sizes
    ios_sizes = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
    
    print("\n🍎 iOS icons:")
    for size in ios_sizes:
        output = f'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-{size}.png'
        create_icon_with_background(svg_path, output, size, 12)
    
    print("\n✅ All icons generated successfully!")
    print("\n📝 Next steps:")
    print("1. For Android: Icons are already in place")
    print("2. For iOS: Update Contents.json in AppIcon.appiconset to reference the new files")
    print("3. Or use flutter_launcher_icons package (see ICON_SETUP_INSTRUCTIONS.md)")

if __name__ == '__main__':
    import os
    
    # Check if SVG exists
    if not os.path.exists('assets/Subtract.svg'):
        print("❌ SVG file not found: assets/Subtract.svg")
        print("   Make sure you're running this from the stocker directory")
        exit(1)
    
    # Create directories if they don't exist
    os.makedirs('assets', exist_ok=True)
    
    try:
        generate_all_sizes()
    except Exception as e:
        print(f"\n❌ Error: {e}")
        print("\nIf you see 'No such file or directory' errors for android/ios paths,")
        print("you can just generate the main icon and use flutter_launcher_icons:")
        print("\n  python generate_app_icon.py --main-only")
        
        if '--main-only' in os.sys.argv:
            create_icon_with_background('assets/Subtract.svg', 'assets/icon_with_bg.png', 1024, 12)
            print("\n✅ Main icon created: assets/icon_with_bg.png")
            print("   Now run: flutter pub run flutter_launcher_icons")
