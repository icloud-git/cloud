#!/bin/bash

# YouTube Premium Region Restriction Check Script
# Extracted and Optimized from RegionRestrictionCheck

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
    else
        curlArgs="$curlArgs -4"
    fi

    echo -n -e "YouTube Premium (IPv${network_type:-4}):\t\t"

    # Request with cookies
    local tmpresult1=$(curl $curlArgs --user-agent "${UA_Browser}" -sSL -H "Accept-Language: en" -b "YSC=BiCUU3-5Gdk; CONSENT=YES+cb.20220301-11-p0.en+FX+700; GPS=1; VISITOR_INFO1_LIVE=4VwPMkB7W5A; PREF=tz=Asia.Shanghai; _gcl_au=1.1.1809531354.1646633279" "https://www.youtube.com/premium" 2>&1)
    # Request without cookies
    local tmpresult2=$(curl $curlArgs --user-agent "${UA_Browser}" -sSL -H "Accept-Language: en" "https://www.youtube.com/premium" 2>&1)
    
    local tmpresult="$tmpresult1:$tmpresult2"

    if [[ "$tmpresult" == "curl"* ]]; then
        echo -e "${Font_Red}Failed (Network Connection)${Font_Suffix}"
        return
    fi

    # Check for China (CN)
    local isCN=$(echo "$tmpresult" | grep 'www.google.cn')
    if [ -n "$isCN" ]; then
        echo -e "${Font_Red}No${Font_Suffix} ${Font_Green}(Region: CN)${Font_Suffix}"
        return
    fi

    # Extract region code and availability
    local region=$(echo "$tmpresult" | grep "countryCode" | sed 's/.*"countryCode"//' | cut -f2 -d'"' | head -n 1)
    local isAvailable=$(echo "$tmpresult" | grep -E 'purchaseButtonOverride|Start trial')

    if [ -n "$isAvailable" ] || [ -n "$region" ]; then
        if [ -n "$region" ]; then
            echo -e "${Font_Green}Yes (Region: $region)${Font_Suffix}"
        else
            echo -e "${Font_Green}Yes${Font_Suffix}"
        fi
    else
        if [ -n "$region" ]; then
            echo -e "${Font_Red}No (Region: $region)${Font_Suffix}"
        else
            echo -e "${Font_Red}No${Font_Suffix}"
        fi
    fi
}

# --- Main ---
echo "======================================="
echo " YouTube Premium Region Check"
echo "======================================="

# Default check for IPv4
check_yt_premium 4

# Check for IPv6 if available (optional)
# check_yt_premium 6

echo "======================================="
