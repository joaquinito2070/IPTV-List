#!/bin/bash

# Define the wordlists.json URL
WORDLISTS_URL="https://raw.githubusercontent.com/kkrypt0nn/wordlists/main/wordlists.json"

# Define the Docker container for yt-dlp
DOCKER_CONTAINER="jauderho/yt-dlp-nightly-builds"

# Define the output file for merged M3U playlists
OUTPUT_FILE="all.m3u"

# Create an empty output file
echo "" > "$OUTPUT_FILE"

# Download wordlists.json
curl -o wordlists.json "$WORDLISTS_URL"

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

  # Extract the M3U URLs from the JSON data - UPDATED JQ COMMAND
  jq -r '.[] | .url' "$lower_code.json" > "$lower_code.urls.txt"  # Store URLs in a temp file
  
  # Check if the URLs file was created
  if [[ ! -f "$lower_code.urls.txt" ]]; then
    echo "Error: Could not extract M3U URLs for $code"
    rm "$lower_code.json"
    continue
  fi

  # Loop through the URLs and get M3U content
  while IFS= read -r url; do
    # Download the M3U playlist
    curl -s "$url" >> "$OUTPUT_FILE"
  done < "$lower_code.urls.txt"

  # Remove the temporary JSON and URLs files
  rm "$lower_code.json"
  rm "$lower_code.urls.txt"

done < country-codes.csv

# Extract all words from the wordlists.json file
jq -r '.[] | .href' wordlists.json > words.json

# Download the wordlists from GitHub
jq -r '.[] | "https://github.com/kkrypt0nn/wordlists/blob/main/" + .href' words.json > wordlists.txt

# Loop through each wordlist
while IFS= read -r wordlist; do
  # Download the wordlist
  curl -s "$wordlist" > wordlist.txt

  # Get YouTube URLs
  docker run -it --rm "$DOCKER_CONTAINER" yt-dlp -f best --extractor-args "youtube:player_client=all,-web,-web_safari" -g "https://www.youtube.com/results?search_query=$(cat wordlist.txt)&sp=EgJAAQ%253D%253D" >> "$OUTPUT_FILE"

  # Get Dailymotion URLs
  docker run -it --rm "$DOCKER_CONTAINER" yt-dlp -f best -g "https://www.dailymotion.com/search/$(cat wordlist.txt)/lives" >> "$OUTPUT_FILE"

  # Remove the temporary wordlist file
  rm wordlist.txt
done < wordlists.txt

# Remove the temporary words.json and wordlists.txt files
rm words.json
rm wordlists.txt
rm wordlists.json

echo "All M3U playlists merged into $OUTPUT_FILE"
