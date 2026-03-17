#!/usr/bin/env node
/**
 * Generate app icon from SVG with white background
 * Uses sharp library (pure JavaScript, no native dependencies)
 */

const fs = require('fs');
const path = require('path');

// Check if sharp is installed
let sharp;
try {
  sharp = require('sharp');
} catch (e) {
  console.log('❌ Sharp library not found. Installing...');
  console.log('   Run: npm install sharp');
  process.exit(1);
}

async function createIconWithBackground(svgPath, outputPath, size = 1024, paddingPercent = 12) {
  try {
    // Calculate dimensions
    const padding = Math.floor(size * paddingPercent / 100);
    const logoSize = size - (2 * padding);
    
    // Read SVG file
    const svgBuffer = fs.readFileSync(svgPath);
    
    // Create white background
    const background = await sharp({
      create: {
        width: size,
        height: size,
        channels: 3,
        background: { r: 255, g: 255, b: 255 }
      }
    }).png();
    
    // Resize SVG to fit with padding
    const logo = await sharp(svgBuffer)
      .resize(logoSize, logoSize, {
        fit: 'contain',
        background: { r: 255, g: 255, b: 255, alpha: 0 }
      })
      .png();
    
    // Composite logo on background
    await background
      .composite([{
        input: await logo.toBuffer(),
        top: padding,
        left: padding
      }])
      .toFile(outputPath);
    
    console.log(`✅ Created ${outputPath} (${size}x${size})`);
    return true;
  } catch (error) {
    console.error(`❌ Error creating ${outputPath}:`, error.message);
    return false;
  }
}

async function main() {
  const svgPath = 'assets/Subtract.svg';
  
  // Check if SVG exists
  if (!fs.existsSync(svgPath)) {
    console.log('❌ SVG file not found:', svgPath);
    console.log('   Make sure you\'re running this from the stocker directory');
    process.exit(1);
  }
  
  console.log('========================================');
  console.log('APEX App Icon Generator (Node.js)');
  console.log('========================================\n');
  
  // Create assets directory if it doesn't exist
  if (!fs.existsSync('assets')) {
    fs.mkdirSync('assets', { recursive: true });
  }
  
  console.log('📱 Generating main icon...');
  const success = await createIconWithBackground(svgPath, 'assets/icon_with_bg.png', 1024, 12);
  
  if (success) {
    console.log('\n✅ Icon generated successfully!');
    console.log('\n📝 Next steps:');
    console.log('1. Run: flutter pub get');
    console.log('2. Run: flutter pub run flutter_launcher_icons');
    console.log('3. Rebuild your app to see the new icon');
  } else {
    console.log('\n❌ Failed to generate icon');
    process.exit(1);
  }
}

// Check if sharp is available
if (typeof sharp === 'undefined') {
  console.log('Installing sharp...');
  const { execSync } = require('child_process');
  try {
    execSync('npm install sharp', { stdio: 'inherit' });
    console.log('✅ Sharp installed. Please run this script again.');
  } catch (e) {
    console.log('❌ Failed to install sharp. Please run manually: npm install sharp');
  }
  process.exit(0);
}

main().catch(error => {
  console.error('❌ Unexpected error:', error);
  process.exit(1);
});
