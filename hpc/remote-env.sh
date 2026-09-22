type module >/dev/null 2>&1 || source /etc/profile
module load singularity
module load nextflow
export JAVA_HOME=/sw/rl9c/java/19.0.1/rl9_binary/jdk-19.0.1
export PATH=$JAVA_HOME/bin:$PATH