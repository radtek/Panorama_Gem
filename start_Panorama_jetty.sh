export PANORAMA_HOME=$PWD
export PANORAMA_PORT=8090
export PANORAMA_USAGE_LOG=$PANORAMA_HOME/Usage.log
export LOG=$PANORAMA_HOME/Panorama_jetty.log
echo "Starting Panorama with jetty, logfile is $LOG"
java -Xmx1024m -XX:MaxPermSize=512M -XX:+CMSClassUnloadingEnabled -XX:+CMSPermGenSweepingEnabled -Djetty.port=8090 -Djetty.requestHeaderSize=8192 -Djava.io.tmpdir=./work -jar $PANORAMA_HOME/Panorama.war 2>&1 | tee -a $LOG 

