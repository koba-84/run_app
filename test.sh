#!/bin/bash

# ベース地点: Googleplex周辺（緯度: 37.4219, 経度: -122.0840）
BASE_LAT=37.4219
BASE_LNG=-122.0840

# ループ回数と間隔（=距離ステップ）
STEPS=1200   # → 仮想的に20分 = 1200秒 = 1200点
INTERVAL=0.00002  # → 約2〜3m間隔

for ((i=0; i<STEPS; i++)); do
  OFFSET=$(echo "$i * $INTERVAL" | bc -l)
  LNG=$(echo "$BASE_LNG + $OFFSET" | bc -l)

  # echo "Sending location: $LNG, $BASE_LAT"
  /Users/ryoma/Library/Android/sdk/platform-tools/adb emu geo fix $LNG $BASE_LAT

  sleep 0.01  # 実行間隔（短くしてもFlutter側でtimestampは +1秒ずつ進む）
done
