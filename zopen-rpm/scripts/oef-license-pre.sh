# License prompt for a pre-install scriptlet (%pre). Pass it to pax2rpm with --pre-script.
# Fails closed: if the answer is not "yes", or there is no terminal to ask on, rpm aborts the install.
cat <<'LICENSE_END'
LICENSE AGREEMENT - IBM Open Enterprise Foundation for z/OS (5655-OEF)

By installing this software, you agree to the following:

This Program is licensed, not sold, under the IBM International Program License Agreement (IPLA). Use is limited to your acquired entitlements.
You may copy and modify Source Components for internal use only.
Third-party components are provided "AS IS" without warranty.
IBM's liability is limited to direct damages up to amounts paid.
IBM is not liable for lost profits or consequential damages.
This license may be terminated if you fail to comply with its terms.
Governing law is based on the country where entitlements were acquired.

LICENSE_END
printf 'Do you accept these terms? [yes/no]: '
read OEF_ANSWER < /dev/tty
case "$OEF_ANSWER" in
  yes|YES|Yes) ;;
  *) echo "License not accepted. Installation cancelled."; exit 1 ;;
esac
