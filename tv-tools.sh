#!/usr/bin/env bash
# ==============================================================================
# TV & Termux Remote Control & Streaming Helper
# ==============================================================================

TV_IP="${TV_IP:-192.168.1.50}" # Replace with your TV's local IP address
TV_PORT="${TV_PORT:-8022}"

usage() {
    echo "Usage: $0 {moonlight|vlc-stream <url_or_path>|audio-sink|adb-key <keycode>}"
    echo ""
    echo "Commands:"
    echo "  moonlight             Launch Moonlight on the TV to stream laptop desktop (sub-15ms)"
    echo "  vlc-stream <url>      Launch VLC on the TV to play a hardware-accelerated video stream"
    echo "  audio-sink            Direct laptop PipeWire/PulseAudio output to TV speakers"
    echo "  adb-key <keycode>     Send remote button press (19=Up, 20=Down, 21=Left, 22=Right, 66=Enter, 4=Back)"
    exit 1
}

case "$1" in
    moonlight)
        echo "[+] Launching Moonlight on TV ($TV_IP:$TV_PORT)..."
        ssh -p "$TV_PORT" "$TV_IP" "am start -n com.limelight/com.limelight.ShortcutTrampoline"
        ;;
    vlc-stream)
        if [ -z "$2" ]; then
            echo "Error: Please provide a video URL or local file."
            exit 1
        fi
        STREAM_URL="$2"
        echo "[+] Playing $STREAM_URL on TV via native VLC..."
        ssh -p "$TV_PORT" "$TV_IP" "am start -a android.intent.action.VIEW -d '$STREAM_URL' -t 'video/*' -n org.videolan.vlc/.gui.video.VideoPlayerActivity"
        ;;
    audio-sink)
        echo "[+] Loading network tunnel sink to TV ($TV_IP:4713)..."
        echo "Make sure TV Termux has: pulseaudio --start --exit-idle-time=-1 --load=\"module-native-protocol-tcp auth-ip-acl=127.0.0.1;192.168.0.0/16 auth-anonymous=1\""
        pactl load-module module-tunnel-sink server=tcp:"$TV_IP":4713 sink_name=tv_soundbar
        echo "[+] Now open your audio settings and set output to 'tv_soundbar'!"
        ;;
    adb-key)
        if [ -z "$2" ]; then
            echo "Error: Specify keycode (e.g. 19 for D-Pad Up, 66 for Select/Enter)"
            exit 1
        fi
        echo "[+] Sending keyevent $2 to TV via Termux ADB loopback..."
        ssh -p "$TV_PORT" "$TV_IP" "adb shell input keyevent $2"
        ;;
    *)
        usage
        ;;
esac
