#!/bin/bash

# ANSI color codes
RED='\033[91m'
RESET='\033[0m'

# ASCII art
echo -e "${RED}"
cat << "EOF"
    _   __           __     _ _____                                 
   / | / /_  _______/ /__  (_) ___/_________ _____  ____  ___  _____
  /  |/ / / / / ___/ / _ \/ /\__ \/ ___/ __ `/ __ \/ __ \/ _ \/ ___/
 / /|  / /_/ / /__/ /  __/ /___/ / /__/ /_/ / / / / / / /  __/ /    
/_/ |_/\__,_/\___/_/\___/_//____/\___/\__,_/_/ /_/_/ /_/\___/_/ 

EOF
echo -e "${RESET}"

# Help menu
display_help() {
    echo -e "NucleiScanner s\n\n"
    echo -e "Usage: $0 [options]\n\n"
    echo "Options:"
    echo "  -h, --help              Display help information"
    echo "  -d, --domain <domain>   Single domain to scan for Unknown Vulnerabilities"
    echo "  -f, --file <filename>   File containing multiple domains/URLs to scan"
    exit 0
}

# Get the current user's home directory
home_dir=$(eval echo ~"$USER")

excluded_extentions="png,jpg,gif,jpeg,swf,woff,svg,pdf,css,webp,woff,woff2,eot,ttf,otf,mp4"

# Parse command line arguments
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        -h|--help)
            display_help
            ;;
        -d|--domain)
            domain="$2"
            shift
            shift
            ;;
        -f|--file)
            filename="$2"
            shift
            shift
            ;;
        *)
            echo "Unknown option: $key"
            display_help
            ;;
    esac
done

# Step 0: Ask the user to enter the domain name or specify the file
if [ -z "$domain" ] && [ -z "$filename" ]; then
    echo "Please provide a domain with -d or a file with -f option."
    display_help
fi

# Step 1: Collect subdomains using subfinder
if [ -n "$domain" ]; then
    echo "Collecting subdomains using subfinder"
    subfinder -d "$domain" -all -silent -o "output/sub.txt"
fi

# Step 2: Collecting URLs by Filtering out unwanted extensions using gauplus
if [ -f "output/sub.txt" ]; then
    echo "Collecting URLs by Filtering out unwanted extensions from 'output/sub.txt' using gauplus"
    cat "output/sub.txt" | gau --blacklist "$excluded_extentions" --o "output/gauplus.txt"
fi

# Step 3: Get the vulnerable parameters based on user input
if [ -n "$domain" ]; then
    echo "Running ParamSpider on $domain"
    python3 "$home_dir/ParamSpider/paramspider.py" -d "$domain" --exclude "$excluded_extentions" --level high --quiet -o "output/$domain.txt"
elif [ -n "$filename" ]; then
    echo "Running ParamSpider on URLs from $filename"
    while IFS= read -r line; do
        python3 "$home_dir/ParamSpider/paramspider.py" -d "$line" --exclude "$excluded_extentions" --level high --quiet -o "output/$line.txt"
        cat "output/$line.txt" >> "$output_file"  # Append to the combined output file
    done < "$filename"
fi

# Step 4: Combine URLs collected by ParamSpider and gauplus
if [ -f "output/gauplus.txt" ]; then
    echo "Combining URLs collected by ParamSpider and gauplus"
    cat "output/$domain.txt" "output/gauplus.txt" > "output/allurls.txt"
    urls_file="output/allurls.txt"
else
    urls_file="output/$domain.txt"
fi

# Step 5: Check whether URLs were collected or not
if [ ! -s "output/$domain.txt" ] && [ ! -s "output/gauplus.txt" ] && [ ! -s "output/allurls.txt" ]; then
    echo "No URLs Found. Exiting..."
    exit 1
fi

# Step 6: Run the Nuclei Scanning templates on the collected URLs
echo "Running Nuclei on Collected URLs"
if [ -n "$domain" ]; then
    # Use a temporary file to store the sorted and unique URLs
    temp_file=$(mktemp)
    sort "$urls_file" | uniq > "$temp_file"
    httpx -silent -mc 200,301,302,403 -l "$temp_file" | nuclei -t "$home_dir/nuclei-templates" -es info -rl 05
    rm -r "$temp_file"  # Remove the temporary file
elif [ -n "$filename" ]; then
    sort "$urls_file" | uniq > "$temp_file"
    httpx -silent -mc 200,301,302,403 -l "$temp_file" | nuclei -t "$home_dir/nuclei-templates" -es info -rl 05
    rm -r "$temp_file"  # Remove the temporary file
fi

# Step 7: End with a general message as the scan is completed
echo "Nuclei Scanning"
