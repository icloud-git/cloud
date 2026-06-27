#!/bin/bash

# YouTube Premium Region Restriction Check Script (v2.2)
# Optimized for Dual-Stack (IPv4/IPv6) support and auto-detection

# --- Colors ---
Font_Red="\033[31m"
Font_Green="\033[32m"
Font_Yellow="\033[33m"
Font_Suffix="\033[0m"

# --- User Agent ---
UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36 Edg/112.0.1722.64"

# --- Functions ---
check_yt_premium() {
    local network_type=$1
    local curlArgs="--max-time 10"
    
    if [ "$network_type" == "6" ]; then
        curlArgs="$curlArgs -6"
        # Pre-check IPv6 connectivity
        if ! curl -6 -s --max-time 3 https://www.youtube.com > /dev/null 2>&1; then
            echo -e "YouTube Premium (IPv6):\t\t${Font_Yellow}Not Supported / No Connectivity${Font_Suffix}"
            return
        fi
    else
        curlArgs="$curlArgs -4"
        # Pre-check IPv4 connectivity
        if ! curl -4 -s --max-time 3 https://www.youtube.com > /dev/null 2>&1; then
            echo -e "YouTube Premium (IPv4):\t\t${Font_Yellow}Not Supported / No Connectivity${Font_Suffix}"
            return
        fi
    fi

    echo -n -e "YouTube Premium (IPv${network_type}):\t\t"

    # Request with optimized headers
    local tmpresult=$(curl $curlArgs --user-agent "${UA_Browser}" -sSL -H "Accept-Language: en" "https://www.youtube.com/premium" 2>&1)

    if [[ "$tmpresult" == "curl"* ]]; then
        echo -e "${Font_Red}Failed (Network Connection)${Font_Suffix}"
        return
    fi

    # 1. Check for China (CN) Special Case
    local isCN=$(echo "$tmpresult" | grep -iE "www.google.cn|youtube.com/redirect?q=http%3A%2F%2Fwww.google.cn")
    if [ -n "$isCN" ]; then
        echo -e "${Font_Red}No${Font_Suffix} ${Font_Green}(Region: CN)${Font_Suffix}"
        return
    fi

    # 2. Extract Region Code (Multiple Methods)
    local region=$(echo "$tmpresult" | grep -oP ":\"countryCode\":\"\K[A-Z]{2}" | head -n 1)
    if [ -z "$region" ]; then
        region=$(echo "$tmpresult" | grep -oP ":\"GL\":\"\K[A-Z]{2}" | head -n 1)
    fi
    if [ -z "$region" ]; then
        region=$(echo "$tmpresult" | grep -oP ":\"INNERTUBE_CONTEXT_GL\":\"\K[A-Z]{2}" | head -n 1)
    fi

    # 3. Check Availability & Reasons
    local isAvailable=$(echo "$tmpresult" | grep -Ei "purchaseButtonOverride|Start trial|Get YouTube Premium")
    local notAvailableMsg=$(echo "$tmpresult" | grep -i "YouTube Premium is not available in your country")

    if [ -n "$isAvailable" ] && [ -z "$notAvailableMsg" ]; then
        if [ -n "$region" ]; then
            echo -e "${Font_Green}Yes (Region: $region)${Font_Suffix}"
        else
            echo -e "${Font_Green}Yes${Font_Suffix}"
        fi
    else
        if [ -n "$region" ]; then
            if [ -n "$notAvailableMsg" ]; then
                echo -e "${Font_Red}No${Font_Suffix} ${Font_Yellow}(Region: $region - Not Available)${Font_Suffix}"
            else
                echo -e "${Font_Red}No${Font_Suffix} ${Font_Yellow}(Region: $region)${Font_Suffix}"
            fi
        else
            echo -e "${Font_Red}No${Font_Suffix}"
        fi
    fi
}

# --- Main ---
echo "======================================="
echo " YouTube Premium Region Check (v2.2)"
echo "======================================="

# Check IPv4
check_yt_premium 4

# Check IPv6
check_yt_premium 6

echo "======================================="
