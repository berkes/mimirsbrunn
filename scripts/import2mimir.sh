#!/usr/bin/env bash

set -o errexit
set -o nounset

if ${DEBUG:-false}; then
  set -x
fi

readonly SCRIPT_SRC="$(dirname "${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}")"
readonly SCRIPT_DIR="$(cd "${SCRIPT_SRC}" >/dev/null 2>&1 && pwd)"
readonly SCRIPT_NAME=$(basename "$0")

APPLICATION="${SCRIPT_NAME%.*}"
VERSION=0.0.1
EXECUTION_DATE=`date '+%Y%m%d'`
LOG_FILE="${APPLICATION}-${EXECUTION_DATE}.log"
CONFIG_FILE="${APPLICATION}.rc"
QUIET=false
DEFAULT_TASK="none"

version()
{
  echo ""
  echo "${APPLICATION}-${VERSION}"
  echo ""
}

usage()
{
  echo ""
  echo "${APPLICATION} - Download data and import into Elasticsearch"
  echo ""
  echo "This file is configured with ${CONFIG_FILE}."
  echo ""
  echo "${APPLICATION} "
  echo "  [ -d ]                Data Directory"
  echo "  [ -V ]                Displays version information"
  echo "  [ -q ]                Quiet, doesn't display to stdout or stderr"
  echo "  [ -h ]                Displays this message"
  echo ""
}

# http://stackoverflow.com/questions/369758/how-to-trim-whitespace-from-bash-variable
trim()
{
  local var=$1
  var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
  var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
  echo -n "$var"
}

# $1: info message string
log_info()
{
    DATE=`date -R`
    if ! $QUIET; then
        echo -e "\e[30;37m$DATE | $1\e[0m"
    fi
    echo "INFO  | $DATE | $1" >> $LOG_FILE
}

# $1: error message string
log_error()
{
    DATE=`date -R`
    if ! $QUIET; then
        echo -e "\e[91m$DATE | $1\e[0m" >&2
    fi
    echo "ERROR | $DATE | $1" >> $LOG_FILE
}

# We check all the executables that will be called in this script.
check_requirements()
{
    log_info "Checking requirements"

    # Check that you have wget, unzip
    command -v wget > /dev/null 2>&1  || { log_error "wget not found. You need to install wget."; return 1; }
    command -v unzip > /dev/null 2>&1  || { log_error "unzip not found. You need to install unzip"; return 1; }

    command -v "${COSMOGONY}" > /dev/null 2>&1  || { log_error "cosmogony not found."; return 1; }
    command -v "${OSM2MIMIR}" > /dev/null 2>&1  || { log_error "osm2mimir not found."; return 1; }
    command -v "${COSMOGONY2MIMIR}" > /dev/null 2>&1  || { log_error "cosmogony2mimir not found"; return 1; }
    command -v "${NTFS2MIMIR}" > /dev/null 2>&1  || { log_error "ntfs2mimir not found."; return 1; }

    return 0
}

# We check the validity of the command line arguments and the configuration
check_arguments()
{
    log_info "Checking arguments"
    # Check that the variable $ES_URL is set and non-empty
    [[ -z "${ES_URL+xxx}" ]] &&
    { log_error "The variable \$ES_URL is not set. Make sure it is set in the configuration file."; usage; return 1; }
    [[ -z "$ES_URL" && "${ES_URL+xxx}" = "xxx" ]] &&
    { log_error "The variable \$ES_URL is set but empty. Make sure it is set in the configuration file."; usage; return 1; }

    # Check that the variable $ES_DATASET is set and non-empty
    [[ -z "${ES_DATASET+xxx}" ]] &&
    { log_error "The variable \$ES_DATASET is not set. Make sure it is set in the configuration file."; usage; return 1; }
    [[ -z "$ES_DATASET" && "${ES_DATASET+xxx}" = "xxx" ]] &&
    { log_error "The variable \$ES_DATASET is set but empty. Make sure it is set in the configuration file."; usage; return 1; }

    return 0
}

# We check the presence of directories (possibly create them), and remote machines.
check_environment()
{
    log_info "Checking environment"
    # Check that the endpoint exists
    # curl -X GET "${ENDPOINT}/_cat/health"
    # [[ $? == 0 ]] && { log_error "An error trying to check the status of Elasticsearch '${ENDPOINT}'"; exit 1; }

    # Check that the data directory exists and is writable.
    # TODO
    return 0
}

# $1: string to search for
# $2: a space delimited list of string
# Returns 1 if $1 was found in $2, 0 otherwise
search_in()
{
  KEY="${1}"
  LIST="${2}"
  OIFS=$IFS
  IFS=" "
  for ELEMENT in ${LIST}
  do
    [[ "${KEY}" = "${ELEMENT}" ]] && { return 1; }
  done
  IFS=$OIFS
  return 0
}

##
# Run a x2mimir command. E.g.
#  run osm2mimir planet.pbf --import-poi --import-way --poi-config poi.json
run()
{

  local command=${1}
  local input=${2}
  local extra_args=${@:3}

  [[ -f "${input}" ]] || { log_error "${command} cannot run: Missing input ${input}"; return 1; }

  ${command} --connection-string "${ES_URL}" --dataset=${ES_DATASET} --input "${input}" ${extra_args}
}

download()
{
  local url=${1}
  local output=${2}
  local extra_args=${@:3}
  if [[ -f ${output} ]]; then
    log_info "Local file ${output} exist. Skipping download from ${url}"
  else
    log_info "Downloading ${output} from ${url}"
    wget --output-document=${output} ${url} ${extra_args}
  fi
}

# Pre requisite: DATA_DIR exists.
generate_cosmogony() {
  log_info "Generating cosmogony"
  mkdir -p "$DATA_DIR/cosmogony"

  local INPUT="${DATA_DIR}/osm/${OSM_REGION}-latest.osm.pbf"
  local OUTPUT="${DATA_DIR}/cosmogony/${OSM_REGION}.json.gz"
  if [[ -f ${OUTPUT} ]]; then
    log_info "Local file ${OUTPUT} exist. Skipping recreation from ${INPUT}"
  else
    # We don't run this with run() since the signature is very different
    "${COSMOGONY}" --country-code NL --input "${INPUT}" --output "${OUTPUT}"
  fi
  [[ $? != 0 ]] && { log_error "Could not generate cosmogony data for ${OSM_REGION}. Aborting"; return 1; }
  return 0
}

# Pre requisite: DATA_DIR exists.
import_cosmogony() {
  log_info "Importing cosmogony into mimir"
  local INPUT="${DATA_DIR}/cosmogony/${OSM_REGION}.json.gz"

  run "${COSMOGONY2MIMIR}" "${INPUT}"
  [[ $? != 0 ]] && { log_error "Could not import cosmogony data from ${DATA_DIR}/cosmogony/${OSM_REGION}.json.gz into mimir. Aborting"; return 1; }
  return 0
}

# Pre requisite: DATA_DIR exists.
import_osm() {
  log_info "Importing osm into mimir"
  local INPUT="${DATA_DIR}/osm/${OSM_REGION}-latest.osm.pbf"
  [[ -f "${INPUT}" ]] || { log_error "osm2mimir cannot run: Missing input ${INPUT}"; return 1; }

  if [[ -f "${OSM_POI_CONFIG}" ]]; then
    local OSM_POI_CONFIG_OPT="--poi-config ${OSM_POI_CONFIG}"
  else
    local OSM_POI_CONFIG_OPT=""
  fi

  run "${OSM2MIMIR}" "${DATA_DIR}/osm/${OSM_REGION}-latest.osm.pbf" ${OSM_POI_CONFIG_OPT} --import-way --import-poi
  [[ $? != 0 ]] && { log_error "Could not import OSM PBF data for ${OSM_REGION} into mimir. Aborting"; return 1; }
  return 0
}

# Pre requisite: DATA_DIR exists.
download_osm() {
  mkdir -p "$DATA_DIR/osm"
  download "${OSM_DOWNLOAD_URL}" "${DATA_DIR}/osm/${OSM_REGION}-latest.osm.pbf"
}

import_oa() {
  log_info "Importing OA into mimir"
  local INPUT="${DATA_DIR}/oa/**/*\.csv"
  run ${OPENADDRESSES2MIMIR} ${INPUT}
  [[ $? != 0 ]] && { log_error "Could not import OA CSV data for ${INPUT} into mimir. Aborting"; return 1; }
  return 0
}

download_oa() {
  mkdir -p "$DATA_DIR/oa"
  local OA_FILE="${DATA_DIR}/oa/$(basename ${OA_DOWNLOAD_URL})"
  download "${OA_DOWNLOAD_URL}" "${OA_FILE}"

  unzip -o -d "${DATA_DIR}/oa/" "${OA_FILE}"
  [[ $? != 0 ]] && { log_error "Could not extract OA CSV data from ${OA_FILE}. Aborting"; return 1; }

  return 0
}

# Pre requisite: DATA_DIR exists.
import_ntfs() {
  log_info "Importing ntfs into mimir"
  run "${NTFS2MIMIR}" "${DATA_DIR}/ntfs"
  [[ $? != 0 ]] && { log_error "Could not import NTFS data from ${DATA_DIR}/ntfs into mimir. Aborting"; return 1; }
  return 0
}

# Pre requisite: DATA_DIR exists.
download_ntfs() {
  mkdir -p "$DATA_DIR/ntfs"
  download "https://navitia.opendatasoft.com/explore/dataset/${NTFS_REGION}/download/?format=csv" "${DATA_DIR}/${NTFS_REGION}.csv"
  [[ $? != 0 ]] && { log_error "Could not download NTFS CSV data for ${NTFS_REGION}. Aborting"; return 1; }
  NTFS_URL=`cat ${DATA_DIR}/${NTFS_REGION}.csv | grep NTFS | cut -d';' -f 5`
  [[ $? != 0 ]] && { log_error "Could not find NTFS URL. Aborting"; return 1; }

  download "${NTFS_URL}" "${DATA_DIR}/ntfs/ntfs.zip" --content-disposition
  rm "${DATA_DIR}/${NTFS_REGION}.csv"
  unzip -o -d "${DATA_DIR}/ntfs" "${DATA_DIR}/ntfs/ntfs.zip"
  [[ $? != 0 ]] && { log_error "Could not unzip NTFS from ${DATA_DIR}/ntfs. Aborting"; return 1; }
  return 0
}

########################### START ############################

while getopts "e:r:d:Vqh" opt; do
    case $opt in
        d) DATA_DIR="$OPTARG";;
        V) version; exit 0 ;;
        q) QUIET=true ;;
        h) usage; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
        :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
    esac
done

# Check that the variable $CONFIG_FILE is set and non-empty
[[ -z "${CONFIG_FILE+xxx}" ]] &&
{ echo -e "\e[91m config filename unset" >&2; echo "\e[0m" >&2; exit 1; }
[[ -z "$CONFIG_FILE" && "${CONFIG_FILE+xxx}" = "xxx" ]] &&
{ echo -e "\e[91m config filename set but empty" >&2; echo "\e[0m" >&2; exit 1; }

# Source $CONFIG_FILE
if [[ -f ${CONFIG_FILE} ]]; then
  log_info "Reading ${CONFIG_FILE}"
  source "${CONFIG_FILE}"
elif [[ -f "${SCRIPT_DIR}/${CONFIG_FILE}" ]]; then
  log_info "Reading ${SCRIPT_DIR}/${CONFIG_FILE}"
  source "${SCRIPT_DIR}/${CONFIG_FILE}"
else
  log_error "Could not find ${CONFIG_FILE} in the current directory or in ${SCRIPT_DIR}"
  exit 1
fi

check_arguments
[[ $? != 0 ]] && { log_error "Invalid arguments. Aborting"; exit 1; }

check_requirements
[[ $? != 0 ]] && { log_error "Invalid requirements. Aborting"; exit 1; }

check_environment
[[ $? != 0 ]] && { log_error "Invalid environment. Aborting"; exit 1; }

# The order in which the import are done into mimir is important!
# First we generate the admin regions with cosmogony
# Second we import the addresses with openaddresses

download_osm
[[ $? != 0 ]] && { log_error "Could not download osm. Aborting"; exit 1; }

# download_ntfs
# [[ $? != 0 ]] && { log_error "Could not download ntfs. Aborting"; exit 1; }

download_oa
[[ $? != 0 ]] && { log_error "Could not download openaddresses. Aborting"; exit 1; }

generate_cosmogony
[[ $? != 0 ]] && { log_error "Could not generate cosmogony. Aborting"; exit 1; }

import_cosmogony
[[ $? != 0 ]] && { log_error "Could not import cosmogony into mimir. Aborting"; exit 1; }

import_oa
[[ $? != 0 ]] && { log_error "Could not import openaddresses into mimir. Aborting"; exit 1; }

import_osm
[[ $? != 0 ]] && { log_error "Could not import osm into mimir. Aborting"; exit 1; }

# import_ntfs
# [[ $? != 0 ]] && { log_error "Could not import ntfs into mimir. Aborting"; exit 1; }
