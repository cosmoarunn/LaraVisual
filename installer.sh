logging() { 
        log_level=$(printf "$1" | /usr/bin/tr '[:lower:]' '[:upper:]') 
    log_statement="$2" 
    script_name="$(/usr/bin/basename $0)" 
    prefix=$(/bin/date +"[%b %d, %Y %Z %T $log_level]:") 
 
    # see if a LOG_PATH has been set 
    if [[ -z "${LOG_PATH}" ]]; then 
        LOG_PATH="/Library/Logs/${script_name}" 
    fi 
 
    if [[ -z $log_level   ]]; then 
                log_level="INFO" 
    fi 
 
    if [[ -z $log_statement   ]]; then 
               log_statement="" 
    fi 
 
        /bin/echo "$prefix $log_statement" 
 
        printf "%s %s\n" "$prefix" "$log_statement" >>"$LOG_PATH" 
 
} 
 
check_brew_install_status() { 
    # Check brew install status. 
    brew_path="$(/usr/bin/find /usr/local/bin /opt -maxdepth 3 -name brew 2>/dev/null)" 
 
    if [[ -n $brew_path   ]]; then 
        # If homebrew is found just run brew update and exit 
        logging "info" "Homebrew already installed at $brew_path ..." 
 
        logging "info" "Updating homebrew ..." 
        /usr/bin/su - "$current_user" -c "$brew_path update --force" | /usr/bin/tee -a "${LOG_PATH}" 
 
        logging "info" "Done ..." 
        exit 0 
 
    else 
        logging "info" "Homebrew is not installed ..." 
    fi 
} 
 
rosetta2_check() { 
    # Check for and install Rosetta2 if needed. 
    # $1: processor_brand 
    # Determine the processor brand 
    if [[ "$1" == *"Apple"* ]]; then 
        logging "info" "Apple Processor is present..." 
 
        # Check if Rosetta is active 

        check_rosetta_status=$(/usr/bin/pgrep oahd) 
 
        # Condition to check to see if the Rosetta folder exists. 

        # the Rosetta2 service is already runs on macOS  11.5+  without 
        # Rosseta2 actually being installed. 
        rosetta_folder="/Library/Apple/usr/share/rosetta" 
 
        if [[ -n $check_rosetta_status ]] && [[ -e $rosetta_folder ]]; then 
            logging "info" "Rosetta2 is installed... no action needed" 
 
        else 
            logging "info" "Rosetta is not installed... installing now" 
 
            # Installs Rosetta 
            /usr/sbin/softwareupdate --install-rosetta --agree-to-license | /usr/bin/tee -a "${LOG_PATH}" 
 
            # Checks the outcome of the Rosetta install 
            if [[ $? -ne 0 ]]; then 
                logging "error" "Rosetta2 install failed..." 
                exit 1 
            fi 
        fi 
 
    else 
        logging "info" "Apple Processor is not present... Rosetta2 not needed" 
    fi 
} 
 
xcode_cli_tools() { 
 
    # Command to check for an Xcode CLI tools path 
    /usr/bin/xcrun --version >/dev/null 2>&1 
 
    # check for valid CLI tools path 
    if [[ $? -eq 0 ]]; then 
        logging "info" "Valid Xcode path found. No need to install Xcode CLI tools ..." 
 
    else 
        logging "info" "Valid Xcode CLI tools path was not found ..." 
 
        # find OS built 
        build_year=$(/usr/bin/sw_vers -buildVersion | cut -c 1,2) 
 
        # Use softwareupdate to learn about xcode cli tools 
        xclt_tmp="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress" 
 
        # create the file above 
        logging "info" "Creating $xclt_tmp ..." 
        /usr/bin/touch "${xclt_tmp}" 
 
        if [[ ${build_year} -ge 19 ]]; then 
            # for Catalina or newer 
            logging "info" "Getting the latest Xcode CLI tools available ..." 
            cmd_line_tools=$(/usr/sbin/softwareupdate -l | awk '/\*\ Label: Command Line Tools/ { $1=$1;print }' | sed 's/^[[ \t]]*//;s/[[ \t]]*$//;s/*//' | cut -c 9-) 
 
        else 
            # For Mojave or older 
            logging "info" "Getting the latest Xcode CLI tools available ..." 
            cmd_line_tools=$(/usr/sbin/softwareupdate -l | /usr/bin/awk '/\*\ Command Line Tools/ { $1=$1;print }' | /usr/bin/grep -i "macOS" | /ussr/bin/sed 's/^[[ \t]]*//;s/[[ \t]]*$//;s/*//' | /usr/bin/cut -c 2-) 
 
        fi 
 
        if [[ "${cmd_line_tools}" == "" ]]; then 
            logging "warning" "Unable to determine available XCode CLI tool updates ..." 
            logging "warning" "This may require manual installation ..." 
 
        else 
            logging "info" "XCode CLI tool updates found: ${cmd_line_tools}" 
        fi 
 
        if (($(/usr/bin/grep -c . <<<"${cmd_line_tools}") > 1)); then 
            cmd_line_tools_output="${cmd_line_tools}" 
            cmd_line_tools=$(printf "${cmd_line_tools_output}" | /usr/bin/tail -1) 
 
            logging "info" "Latest Xcode CLI tools found: $cmd_line_tools" 
        fi 
 
        # run softwareupdate to install xcode cli tools 
        logging "info" "Installing the latest Xcode CLI tools ..." 
 
        # Send output to the local homebrew_install.log as well as stdout 
        /usr/sbin/softwareupdate -i "${cmd_line_tools}" --verbose | /usr/bin/tee -a "${LOG_PATH}" 
 
        # cleanup the temp file 
        logging "info" "Cleaning up $xclt_tmp ..." 
        /bin/rm "${xclt_tmp}" 
 
    fi 
} 
 
set_brew_prefix() { 
    # Set the homebrew prefix. 
    # Set the brew prefix to either the Apple Silicon location or the Intel location based on the 
    # processor_brand information 
    # 
    # $1: proccessor brand information 
    local brew_prefix 
 
    if [[ $1 == *"Apple"* ]]; then 
        # set brew prefix for Apple Silicon 
        brew_prefix="/opt/homebrew" 
    else 
        # set brew prefix for Intel 
        brew_prefix="/usr/local" 
    fi 
 
    # return the brew_prefix 
    /bin/echo "$brew_prefix" 
} 
 
create_brew_environment() { 
    # Create the brew environment. 
        # $1: brew_prefix 
    # $2: current_user 
    logging "info" "Creating directories required by brew ..." 
    /bin/mkdir -p "${1}/Caskroom" "${1}/Cellar" "${1}/Frameworks" "${1}/Homebrew" "${1}/bin" "${1}/etc" "${1}/include" "${1}/lib" "${1}/opt" "${1}/sbin" "${1}/man/man1" "${1}/share/doc" "${1}/share/man/man1" "${1}/share/zsh/site-functions" "${1}/var" "${1}/var/homebrew/linked" 
 
    logging "info" "Creating symlink to ${1}/bin/brew ..." 
    /bin/ln -s "${1}/Homebrew/bin/brew" "${1}/bin/brew" 
 
    logging "info" "Setting homebrew ownership to $2 ..." 
    /usr/sbin/chown -R "$2" "${1}/Cellar" "${1}/Caskroom" "${1}/Frameworks" "${1}/Homebrew" "${1}/bin" "${1}/bin/brew" "${1}/etc" "${1}/include" "${1}/lib" "${1}/man" "${1}/opt" "${1}/sbin" "${1}/share" "${1}/var" 
 
    logging "info" "Setting permissions for brew directories and files ..." 
    /bin/chmod -R 755 "${1}/Homebrew" "${1}/Cellar" "${1}/Caskroom" "${1}/Frameworks" "${1}/bin" "${1}/bin/brew" "${1}/etc" "${1}/include" "${1}/lib" "${1}/man" "${1}/opt" "${1}/sbin" "${1}/share" "${1}/var" 
 
} 
 
reset_source() { 
    # Reset the shell source so that brew doctor will find brew in the user's PATH 
    if [[ "/Users/$current_user/.zshrc" ]]; then 
        /usr/bin/su - "$current_user" -c source "/Users/$current_user/.zshrc" | /usr/bin/tee -a "${LOG_PATH}" 
    fi 
 
    if [[ "/Users/$current_user/.bashrc" ]]; then 
        /usr/bin/su - "$current_user" -c source "/Users/$current_user/.bashrc" | /usr/bin/tee -a "${LOG_PATH}" 
    fi 
 
} 
 
brew_doctor() { 
    # Check Homebrew install status 
    # 
    # On Apple Silicon macs you may see the following output from brew doctor 
   
    # $1: brew_prefix 
    # $2: current_user 
 
    /usr/bin/su - "$2" -c "$1/bin/brew doctor" 2>&1 | /usr/bin/tee -a "${LOG_PATH}" 
 
    if [[ $? -ne 0 ]]; then 
        logging "error" "brew doctor has errors. Review logs to see if action needs to be taken ..." 
    else 
        logging "info" "Homebrew installation complete! Your system is ready to brew." 
    fi 
} 
 
 
############################ DO NOT MODIFY BELOW ##################################### 
 
 
#Modify at your own risk. 
 
logging "info" "--- Start homebrew install log ---" 
/bin/echo "Log file at /Library/Logs/homebrew_install.log" 
 
# Get the processor brand information 
processor_brand="$(/usr/sbin/sysctl -n machdep.cpu.brand_string)" 
 
# Get the current logged in user excluding loginwindow, _mbsetupuser, and root 
current_user=$(/usr/sbin/scutil <<<"show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ && ! /root/ && ! /_mbsetupuser/ { print $3 }' | /usr/bin/awk -F '@' '{print $1}') 
 
# Make sure that we can find the most recent logged in user 
if [[ $current_user == "" ]]; then 
    logging "info" "Current user not logged in ..." 
    logging "info" "Attempting to determine the most common user..." 
 
    # Because someone other than the current user was returned, we are going to look at who uses 
    # the this Mac the most and then set current user to that user. 
    current_user=$(/usr/sbin/ac -p | /usr/bin/sort -nk 2 | /usr/bin/grep -E -v "total|admin|root|mbsetup|adobe" | /usr/bin/tail -1 | /usr/bin/xargs | /usr/bin/cut -d " " -f1) 
 
fi 
 
logging "info" "Most common user: $current_user" 
 
# Verify the current_user is valid 
if /usr/bin/dscl . -read "/Users/$current_user" >/dev/null 2>&1; then 
    logging "info" "$current_user is a valid user ..." 
 
else 
    logging "error" "Specified user \"$current_user\" is invalid" 
    exit 1 
 
fi 
 
logging "info" "Checking to see if Homebew is already install on this Mac ..." 
check_brew_install_status 
 
logging "info" "Checking to see if Rosetta2 is needed ..." 
rosetta2_check "$processor_brand" 
 
logging "info" "Checking to see if Xcode cli tools are needed ..." 
xcode_cli_tools 
 
logging "info" "Determining Homebrew path prefix ..." 
brew_prefix=$(set_brew_prefix $processor_brand) 
 
logging "info" "Creating the Homebrew directory at $brew_prefix/Homebrew ..." 
/bin/mkdir -p "$brew_prefix/Homebrew" 
 
logging "info" "Downloading homebrew ..." 
 
# Using curl to download the latest release of homebrew tarball  

 
/usr/bin/curl --fail --silent --show-error --location --url "https://github.com/Homebrew/brew/tarball/master" | /usr/bin/tar xz --strip 1 -C "$brew_prefix/Homebrew" | /usr/bin/tee -a "${LOG_PATH}" 
 
# Check to see if brew was downloaded  

 

if [[ -f "$brew_prefix/Homebrew/bin/brew" ]]; then 
    logging "info" "Homebrew binary found at $brew_prefix/Homebrew/bin/brew ..." 
    logging "info" "Creating the brew environment ..." 
    create_brew_environment "$brew_prefix" "$current_user" 
 
else 
    logging "info" "Homebrew binary not found ..." 
    /bin/echo "Check $LOG_PATH for more details ..." 
    exit 1 
 
fi 
 
logging "info" "Running brew update --force ..." 
/usr/bin/su - "$current_user" -c "$brew_prefix/bin/brew update --force" 2>&1 | /usr/bin/tee -a "${LOG_PATH}" 
 
logging "info" "Running brew cleanup ..." 
/usr/bin/su - "$current_user" -c "$brew_prefix/bin/brew cleanup" 2>&1 | /usr/bin/tee -a "${LOG_PATH}" 
 
# Check for missing PATH 
get_path_cmd=$(/usr/bin/su - "$current_user" -c "$brew_prefix/bin/brew doctor 2>&1 | /usr/bin/grep 'export PATH=' | /usr/bin/tail -1") 
 
# Add Homebrew's "bin" to target user PATH 
if [[ -n ${get_path_cmd} ]]; then 
    logging "info" "Adding brew to path" 
    /usr/bin/su - "$current_user" -c "${get_path_cmd}" 
fi 
 
logging "info" "Resetting the user's shell source file so that brew doctor can find it..." 
reset_source 
 
logging "info" "Running brew doctor to validate the install ..." 
brew_doctor "$brew_prefix" "$current_user" 
 
logging "info" "--- End homebrew install log ---" 
 
exit 0 