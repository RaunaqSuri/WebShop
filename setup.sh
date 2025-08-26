#!/bin/bash
set -e
# Displays information on how to use script
helpFunction()
{
  echo "Usage: $0 [-d small|all]"
  echo -e "\t-d small|all - Specify whether to download entire dataset (all) or just 1000 (small)"
  exit 1 # Exit script after printing help
}

# Get values of command line flags
while getopts d: flag
do
  case "${flag}" in
    d) data=${OPTARG};;
  esac
done

if [ -z "$data" ]; then
  echo "[ERROR]: Missing -d flag"
  helpFunction
fi

# Install Python Dependencies
echo "Installing Python dependencies from requirements.txt..."
python -m pip install -r requirements.txt

# Install Environment Dependencies via `conda`
echo "Installing Conda dependencies..."
conda install -y -c pytorch faiss-cpu
conda install -y -c conda-forge openjdk=11

# Download dataset into `data` folder
echo "Downloading dataset..."
mkdir -p data
cd data
if [ "$data" == "small" ]; then
  cp /mnt/webshop_data/items_shuffle_1000.json .; # items_shuffle_1000
  cp /mnt/webshop_data/items_ins_v2_1000.json .; # items_ins_v2_1000
elif [ "$data" == "all" ]; then
  cp /mnt/webshop_data/items_shuffle.json .; # items_shuffle
  cp /mnt/webshop_data/items_ins_v2.json .; # items_ins_v2
else
  echo "[ERROR]: argument for `-d` flag not recognized"
  helpFunction
fi
cp /mnt/webshop_data/items_humans_ins.json . # items_human_ins
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
cp /mnt/webshop_data/all_trajs/* .
echo "Downloading example trajectories complete"
cd ..

echo "✅ Setup script finished."