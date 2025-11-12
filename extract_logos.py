
import zipfile
import os

def extract_zip(zip_path, extract_path):
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(extract_path)

logos_dir = 'logos'
nixos_zip = os.path.join(logos_dir, 'nixos-logo-all-variants.zip')

extract_zip(nixos_zip, logos_dir)

os.remove(nixos_zip)
