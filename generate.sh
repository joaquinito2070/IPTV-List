#!/bin/bash

# Variables
WORDLISTS_JSON_URL="https://github.com/kkrypt0nn/wordlists/blob/main/wordlists.json"
COUNTRIES_CSV="countries.csv"
FINAL_M3U="all.m3u"
DOCKER_IMAGE="jauderho/yt-dlp-nightly-builds"

# Funciones auxiliares

# Descargar un archivo y manejar posibles errores de red
download_file() {
  local url=$1
  local output_file=$2

  if ! wget -q -O "$output_file" "$url"; then
    echo "Error al descargar $url" >&2 
    return 1
  fi
}

# Extraer URLs de M3U, saltando líneas inválidas
extract_m3u_urls() {
  local m3u_file=$1

  grep -E "^https?://" "$m3u_file" | sed 's/^[ \t]*//'
}

# Construir una consulta de búsqueda a partir de palabras clave
build_search_query() {
  local keywords=$1

  echo "$keywords" | sed 's/ /+/g' 
}

# Obtener URLs de YouTube usando yt-dlp en Docker
get_youtube_urls() {
  local search_query=$1

  local youtube_url="https://www.youtube.com/results?search_query=$search_query&sp=EgJAAQ%253D%253D"
  docker run -it --rm "$DOCKER_IMAGE" \
    yt-dlp -f best --extractor-args "youtube:player_client=all,-web,-web_safari" -g "$youtube_url"
}

# Obtener URLs de Dailymotion usando yt-dlp en Docker
get_dailymotion_urls() {
  local search_query=$1

  local dailymotion_url="https://www.dailymotion.com/search/$search_query/lives"
  docker run -it --rm "$DOCKER_IMAGE" yt-dlp -g "$dailymotion_url"
}

# 1. Descargar y procesar wordlists.json

download_file "$WORDLISTS_JSON_URL" "wordlists.json"

# Extraer URLs de diccionarios y descargarlos
jq -r '.[] | .href' "wordlists.json" | while read -r dict_url; do
  download_file "https://github.com/$dict_url" "$(basename "$dict_url")"
done

# Combinar todas las palabras de los diccionarios en una sola variable
all_keywords=$(cat *.txt | tr ' ' '\n' | sort -u | tr '\n' ' ')

# 2. Procesar cada país del CSV

# Crear el archivo final M3U
touch "$FINAL_M3U"

while IFS="," read -r country_name country_code; do
  country_code=$(echo "$country_code" | tr '[:upper:]' '[:lower:]')

  # Descargar JSON de país, manejar 404
  megacubo_json_url="https://app.megacubo.net/stats/data/country-sources.$country_code.json"
  if ! download_file "$megacubo_json_url" "country.json"; then
    continue  # Saltar al siguiente país si hay un error 404
  fi

  # Extraer URLs de M3U de cada elemento JSON, manejar listas inválidas
  jq -r '.[] | .url' "country.json" | while read -r m3u_url; do
    if ! download_file "$m3u_url" "temp.m3u"; then
      continue 
    fi

    if ! grep -q "#EXTM3U" "temp.m3u"; then
      continue  # Saltar a la siguiente lista si no es un M3U válido
    fi

    extract_m3u_urls "temp.m3u" >> "$FINAL_M3U"
    rm "temp.m3u"
  done

  rm "country.json" 
done < "$COUNTRIES_CSV"

# 3. Obtener URLs de YouTube y Dailymotion

search_query=$(build_search_query "$all_keywords")

get_youtube_urls "$search_query" >> "$FINAL_M3U"
get_dailymotion_urls "$search_query" >> "$FINAL_M3U"

# Limpieza final
rm *.txt *.json

echo "Proceso completado. El archivo M3U final se encuentra en $FINAL_M3U"
