# Post-install steps for the IBM Z Atlas Discovery Agent RPM.
# These are the "Prepare files" commands from the agent README (step 3),
# plus a restrictive mode on config.yaml, which will hold Vault credentials.
# It does not run setup_and_verify.sh. That script edits ~/.profile and installs Python packages.
D=/opt/pkg/share/zps-discovery-agent/misc
chmod +x $D/run.sh $D/setup_and_verify.sh
chmod 600 $D/config.yaml
chtag -tc ISO8859-1 $D/setup_and_verify.sh $D/run.sh $D/config.yaml
