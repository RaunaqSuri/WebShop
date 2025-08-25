#!/bin/bash

# --- Helper and Download Functions ---

# Displays information on how to use the script
helpFunction() {
   echo ""
   echo "Usage: $0 -d <small|all> -t <gdrive_token>"
   echo -e "\t-d small|all\tSpecify whether to download the full dataset (all) or a small sample (small)."
   echo -e "\t-t <gdrive_token>\tYour Google Drive API access token."
   exit 1 # Exit script after printing help
}

# Downloads a single file from a Google Drive URL using curl and the Drive API.
#
# @param {string} url The full Google Drive URL.
# @param {string} access_token The Google Drive API access token.
# @param {string} output_dir The directory where the file will be saved.
#
download_gdrive_file() {
    # Assign arguments to local variables for clarity
    local url="$1"
    local access_token="$2"
    local output_dir="$3"

    # 1. Check for required dependencies
    if ! command -v jq &> /dev/null; then
        echo "❌ Error: 'jq' is not installed. Please install it to proceed."
        return 1
    fi

    # 2. Extract the file ID from either '/d/FILE_ID/' or '?id=FILE_ID' URL formats
    echo "Processing URL: $url"
    local FILE_ID
    FILE_ID=$(echo "$url" | grep -oP '(d/|id=)\K[^/&]+')

    if [[ -z "$FILE_ID" ]]; then
        echo "❌ Error: Could not extract a valid File ID from the URL."
        return 1
    fi
    echo "🔍 File ID found: $FILE_ID"

    # 3. Get file metadata (specifically the name) using the Drive API
    local FILE_METADATA
    FILE_METADATA=$(curl -s -H "Authorization: Bearer $access_token" \
        "https://www.googleapis.com/drive/v3/files/$FILE_ID?fields=name")
    
    local ORIGINAL_NAME
    ORIGINAL_NAME=$(echo "$FILE_METADATA" | jq -r '.name')

    if [[ -z "$ORIGINAL_NAME" || "$ORIGINAL_NAME" == "null" ]]; then
        echo "❌ Error: Failed to retrieve file metadata. Check if your token is valid and has permission."
        return 1
    fi

    # 4. Download the file content
    local OUTPUT_FILE="$output_dir/$ORIGINAL_NAME"
    echo "🔽 Downloading '$ORIGINAL_NAME' to '$OUTPUT_FILE'..."

    curl -L --fail -H "Authorization: Bearer $access_token" \
        "https://www.googleapis.com/drive/v3/files/$FILE_ID?alt=media" \
        -o "$OUTPUT_FILE"

    # 5. Check if the download was successful
    if [[ $? -eq 0 ]]; then
        echo "✅ Download complete!"
    else
        echo "❌ Download failed."
        return 1
    fi
}

# --- Script Execution ---

# Initialize variables
data=""
gdrive_token=""

# Get values of command line flags
while getopts "d:t:" flag; do
  case "${flag}" in
    d) data=${OPTARG};;
    t) gdrive_token=${OPTARG};;
    ?) helpFunction ;;
  esac
done

# Check for missing mandatory flags
if [ -z "$data" ]; then
  echo "[ERROR]: Missing -d flag"
  helpFunction
fi

if [ -z "$gdrive_token" ]; then
  echo "[ERROR]: Missing -t flag for the GDRIVE access token"
  helpFunction
fi

# Install Python Dependencies
echo "Installing Python dependencies from requirements.txt..."
pip install -r requirements.txt

# Install Environment Dependencies via `conda`
echo "Installing Conda dependencies..."
conda install -y -c pytorch faiss-cpu
conda install -y -c conda-forge openjdk=11

# Download dataset into `data` folder
echo "Downloading dataset..."
mkdir -p data
cd data
if [ "$data" == "small" ]; then
  download_gdrive_file "https://drive.google.com/uc?id=1EgHdxQ_YxqIQlvvq5iKlCrkEKR6-j0Ib" "$gdrive_token" "." # items_shuffle_1000
  download_gdrive_file "https://drive.google.com/uc?id=1IduG0xl544V_A_jv3tHXC0kyFi7PnyBu" "$gdrive_token" "." # items_ins_v2_1000
elif [ "$data" == "all" ]; then
  download_gdrive_file "https://drive.google.com/uc?id=1A2whVgOO0euk5O13n2iYDM0bQRkkRduB" "$gdrive_token" "." # items_shuffle
  download_gdrive_file "https://drive.google.com/uc?id=1s2j6NgHljiZzQNL3veZaAiyW_qDEgBNi" "$gdrive_token" "." # items_ins_v2
else
  echo "[ERROR]: argument for '-d' flag not recognized"
  helpFunction
fi
download_gdrive_file "https://drive.google.com/uc?id=14Kb5SPBk_jfdLZ_CDBNitW98QLDlKR5O" "$gdrive_token" "." # items_human_ins
cd ..

# Download spaCy large NLP model
echo "Downloading spaCy NLP model..."
python -m spacy download en_core_web_lg

# Build search engine index
echo "Building search engine index..."
cd search_engine
mkdir -p resources resources_100 resources_1k resources_100k
python convert_product_file_format.py
mkdir -p indexes
./run_indexing.sh
cd ..

# Create logging folder + samples of log data
get_human_trajs () {
  # Note: This part still uses the `gdown` Python library as it's downloading a folder,
  # which is more complex than downloading a single file via the API in bash.
  PYCMD=$(cat <<EOF
import gdown
url="https://drive.google.com/drive/u/1/folders/16H7LZe2otq4qGnKw_Ic1dkt-o3U9Zsto"
gdown.download_folder(url, quiet=True, remaining_ok=True)
EOF
  )
  python -c "$PYCMD"
}
mkdir -p user_session_logs/
cd user_session_logs/
echo "Downloading 50 example human trajectories..."
get_human_trajs
echo "Downloading example trajectories complete"
cd ..

echo "✅ Setup script finished."