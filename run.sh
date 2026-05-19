#!/bin/bash
# MacSynergy Phase 1 Run Script

# Stop any currently running instances of MacSynergy
echo "🛑 Checking for running MacSynergy instances..."
pkill -x MacSynergy 2>/dev/null || true
sleep 0.5

# Compile the project in release mode for maximum speed and optimal NPU language processing
echo "🔨 Building MacSynergy in release mode..."
if swift build -c release; then
    echo "✅ Build successful!"
    
    # Run the compiled application in the background
    echo "🚀 Launching MacSynergy in accessory/overlay mode..."
    nohup .build/release/MacSynergy >/dev/null 2>&1 &
    
    echo ""
    echo "🎉 MacSynergy is now running on your Mac!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⌨️  Press [ Shift + Space ] to toggle the search bar!"
    echo "❌ Press [ Escape ] or click outside the bar to dismiss it!"
    echo "🇰🇷 Try typing Korean ('안녕하세요') or English ('Hello') to see on-device language detection!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "❌ Error: Build failed."
    exit 1
fi
