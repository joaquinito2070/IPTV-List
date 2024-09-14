#!/bin/bash

# Define the wordlists.json URL
WORDLISTS_URL="https://github.com/kkrypt0nn/wordlists/blob/main/wordlists.json"

# Define the Docker container for yt-dlp
DOCKER_CONTAINER="jauderho/yt-dlp-nightly-builds"

# Define the output file for merged M3U playlists
OUTPUT_FILE="all.m3u"

# Create an empty output file
echo "" > "$OUTPUT_FILE"

# Loop through each country code
while IFS=, read -r name code; do
  # Convert country code to lowercase
  lower_code=$(echo "$code" | tr '[:upper:]' '[:lower:]')

  # Construct the JSON data URL
  json_url="https://app.megacubo.net/stats/data/country-sources.$lower_code.json"

  # Download the JSON data
  curl -s "$json_url" > "$lower_code.json"

  # Check if the download was successful
  if [[ $? -ne 0 ]]; then
    echo "Error: Could not download JSON data for $code"
    rm "$lower_code.json"
    continue
  fi

  # Extract the M3U URLs from the JSON data
  jq -r '.[] | .url' "$lower_code.json" > "$lower_code.m3u"

  # Check if the M3U file was created
  if [[ ! -f "$lower_code.m3u" ]]; then
    echo "Error: Could not extract M3U URLs for $code"
    rm "$lower_code.json"
    continue
  fi

  # Check if the M3U file contains #EXTM3U
  if grep -q '#EXTM3U' "$lower_code.m3u"; then
    # Merge the M3U file into the output file
    cat "$lower_code.m3u" >> "$OUTPUT_FILE"
  else
    echo "Error: M3U file for $code does not contain #EXTM3U"
  fi

  # Remove the temporary JSON and M3U files
  rm "$lower_code.json"
  rm "$lower_code.m3u"

done < <(cat country-codes.csv)

# Extract all words from the wordlists.json file
jq -r '.[] | .href' "$WORDLISTS_URL" > words.json

# Download the wordlists from GitHub
jq -r '.[] | "https://github.com/kkrypt0nn/wordlists/blob/main/" + .href' words.json > wordlists.txt

# Loop through each wordlist
while IFS= read -r wordlist; do
  # Download the wordlist
  curl -s "$wordlist" > wordlist.txt

  # Get YouTube URLs
  docker run -it --rm "$DOCKER_CONTAINER" yt-dlp -f best --extractor-args "youtube:player_client=all,-web,-web_safari" -g "https://www.youtube.com/results?search_query=$(cat wordlist.txt)&sp=EgJAAQ%253D%253D" >> "$OUTPUT_FILE"

  # Get Dailymotion URLs
  docker run -it --rm "$DOCKER_CONTAINER" yt-dlp -g "https://www.dailymotion.com/search/$(cat wordlist.txt)/lives" >> "$OUTPUT_FILE"

  # Remove the temporary wordlist file
  rm wordlist.txt
done < wordlists.txt

# Remove the temporary words.json and wordlists.txt files
rm words.json
rm wordlists.txt

echo "All M3U playlists merged into $OUTPUT_FILE"
