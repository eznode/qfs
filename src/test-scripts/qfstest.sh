#!/bin/sh
#
# $Id$
#
# Created 2010/07/16
# Author: Mike Ovsiannikov
#
# Copyright 2010-2012,2016 Quantcast Corporation. All rights reserved.
#
# This file is part of Kosmos File System (KFS).
#
# Licensed under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied. See the License for the specific language governing
# permissions and limitations under the License.
#
#

csrpctrace=${rpctrace-0}
trdverify=${trdverify-0}
s3debug=0
jerasuretest=''

while [ $# -ge 1 ]; do
    if [ x"$1" = x'-valgrind' ]; then
        myvalgrind='valgrind -v --log-file=valgrind.log --leak-check=full --leak-resolution=high --show-reachable=yes --track-origins=yes'
        GLIBCPP_FORCE_NEW=1
        export GLIBCPP_FORCE_NEW
        GLIBCXX_FORCE_NEW=1
        export GLIBCXX_FORCE_NEW
    elif [ x"$1" = x'-ipv6' ]; then
        testipv6='yes'
    elif [ x"$1" = x'-noauth' ]; then
        auth='no'
    elif [ x"$1" = x'-s3' ]; then
        s3test='yes'
    elif [ x"$1" = x'-s3debug' ]; then
        s3test='yes'
        s3debug=1
    elif [ x"$1" = x'-auth' ]; then
        auth='no'
    elif [ x"$1" = x'-csrpctrace' ]; then
        csrpctrace=1
    elif [ x"$1" = x'-jerasure' ]; then
        jerasuretest='yes'
    elif [ x"$1" = x'-no-jerasure' ]; then
        jerasuretest='no'
    else
        echo "unsupported option: $1" 1>&2
        echo "Usage: $0 [-valgrind] [-ipv6] [-noauth] [-auth]" \
            "[-s3 | -s3debug] [-csrpctrace] [-trdverify]" \
            "[-jerasure | -no-jerasure]"
        exit 1
    fi
    shift
done

if [ x"$s3test" = x'yes' ]; then
    if [ x"$QFS_S3_ACCESS_KEY_ID" = x -o \
            x"$QFS_S3_SECRET_ACCESS_KEY" = x -o \
            x"$QFS_S3_BUCKET_NAME" = x ]; then
        echo "environment variables QFS_S3_ACCESS_KEY_ID," \
            "QFS_S3_SECRET_ACCESS_KEY," \
            "QFS_S3_BUCKET_NAME, and optionally"\
            "QFS_S3_REGION_NAME must be set accordintly"
        exit 1
    fi
    if [ x"$QFS_S3_REGION_NAME" = x ]; then
        s3serversideencryption=${s3serversideencryption-0}
    else
        s3serversideencryption=${s3serversideencryption-1}
    fi
fi

export myvalgrind

exec </dev/null
cd ${1-.} || exit

if openssl version | grep 'OpenSSL 1\.' > /dev/null; then
    auth=${auth-yes}
else
    auth=${auth-no}
fi
if [ x"$auth" = x'yes' ]; then
    echo "Authentication on"
fi

if [ x"$testipv6" = x'yes' ]; then
    metahost='::1'
    metahosturl="[$metahost]"
    iptobind='::'
else
    metahost='127.0.0.1'
    # metahost='localhost'
    metahosturl=$metahost
    iptobind='0.0.0.0'
fi

clientuser=${clientuser-"`id -un`"}

numchunksrv=${numchunksrv-3}
metasrvport=${metasrvport-20200}
testdir=${testdir-`pwd`/`basename "$0" .sh`}
objectstorebuffersize=${objectstorebuffersize-`expr 500 \* 1024`}

export metahost
export metasrvport
export metahosturl

unset QFS_CLIENT_CONFIG
unset QFS_CLIENT_CONFIG_127_0_0_1_${metasrvport}

# kfanout_test.sh parameters
fanouttestsize=${fanouttestsize-1e5}
fanoutpartitions=${fanoutpartitions-3}
kfstestnoshutdownwait=${kfstestnoshutdownwait-}

metasrvchunkport=`expr $metasrvport + 100`
chunksrvport=`expr $metasrvchunkport + 100`
metasrvdir="$testdir/meta"
chunksrvdir="$testdir/chunk"
metasrvprop='MetaServer.prp'
metasrvlog='metaserver.log'
pidsuf='.pid'
metasrvpid="metaserver${pidsuf}"
metaservercreatefsout='metaservercreatefs.out'
metasrvout='metaserver.out.log'
chunksrvprop='ChunkServer.prp'
chunksrvlog='chunkserver.log'
chunksrvpid="chunkserver${pidsuf}"
chunksrvout='chunkserver.out.log'
csallowcleartext=${csallowcleartext-1}
clustername='qfs-test-cluster'
clientprop="$testdir/client.prp"
clientrootprop="$testdir/clientroot.prp"
certsdir=${certsdir-"$testdir/certs"}
minrequreddiskspace=${minrequreddiskspace-6.5e9}
minrequreddiskspacefanoutsort=${minrequreddiskspacefanoutsort-11e9}
lowrequreddiskspace=${lowrequreddiskspace-20e9}
lowrequreddiskspacefanoutsort=${lowrequreddiskspacefanoutsort-30e9}
chunkserverclithreads=${chunkserverclithreads-3}
csheartbeatinterval=${csheartbeatinterval-5}
cptestextraopts=${cptestextraopts-}
mkcerts=`dirname "$0"`
mkcerts="`cd "$mkcerts" && pwd`/qfsmkcerts.sh"

if [ x"$myvalgrind" = x ]; then
    true
else
    metastartwait='yes' # wait for unit test to finish
fi
[ x"`uname`" = x'Darwin' ] && dontusefuser=yes
if [ x"$dontusefuser" = x'yes' ]; then
    true
else
    fuser "$0" >/dev/null 2>&1 || dontusefuser=yes
fi
export myvalgrind

# cptest.sh parameters
sizes=${sizes-'0 1 2 3 127 511 1024 65535 65536 65537 70300 1e5 10e6 100e6 250e6'}
meta=${meta-"-s $metahost -p $metasrvport"}
export sizes
export meta
if find "$0" -type f -print0 2>/dev/null \
        | xargs -0 echo > /dev/null 2>/dev/null; then
    findprint=-print0
    xargsnull=-0
else
    findprint=-print
    xargsnull=''
fi

findpids()
{
    find . -name \*"${pidsuf}" $findprint | xargs $xargsnull ${1+"$@"}
}

getpids()
{
   findpids cat
}

showpids()
{
    findpids grep -v x /dev/null
}

myrunprog()
{
    p=`which "$1"`
    shift
    if [ x"$myvalgrind" = x ]; then
        exec "$p" ${1+"$@"}
    else
        eval exec "$myvalgrind" '"$p" ${1+"$@"}'
    fi
}

ensurerunning()
{
    rem=${2-10}
    until kill -0 "$1"; do
        rem=`expr $rem - 1`
        [ $rem -le 0 ] && return 1
        sleep 1
    done
    return 0
}

mytailpids=''

mytailwait()
{
    exec tail -1000f "$2" &
    mytailpids="$mytailpids $!"
    wait $1
    myret=$?
    return $myret
}

waitqfscandcptests()
{
    mytailwait $qfscpid test-qfsc.out
    qfscstatus=$?
    rm "$qfscpidf"

    if [ x"$accessdir" = x ]; then
        kfsaccessstatus=0
    else
        mytailwait $kfsaccesspid kfsaccess_test.out
        kfsaccessstatus=$?
        rm "$kfsaccesspidf"
    fi

    mytailwait $cppid cptest.out
    cpstatus=$?
    rm "$cppidf"
}

fodir='src/cc/fanout'
smsdir='src/cc/sortmaster'
if [ x"$sortdir" = x -a \( -d "$smsdir" -o -d "$fodir" \) ]; then
    sortdir="`dirname "$0"`/../../../sort"
fi
if [ -d "$sortdir" ]; then
    sortdir=`cd "$sortdir" >/dev/null 2>&1 && pwd`
else
    sortdir=''
fi

if [ x"$sortdir" = x ]; then
    smtest=''
    fodir=''
    fosdir=$fodir
    fotest=0
else
    smdir="$sortdir/$smsdir"
    smdir=`cd "$smdir" >/dev/null 2>&1 && pwd`
    builddir="`pwd`/src/cc"
    export builddir
    metaport=$metasrvport
    export metaport
    smtest="$smdir/sortmaster_test.sh"
    if [ x"$myvalgrind" = x ]; then
        smtestqfsvalgrind='no'
    else
        smtestqfsvalgrind='yes'
    fi
    export smtestqfsvalgrind
# Use QFS_CLIENT_CONFIG for sort master.
#    if [ x"$auth" = x'yes' ]; then
#        smauthconf="$testdir/sortmasterauth.prp"
#        export smauthconf
#    fi
    for name in \
            "$smsdir/ksortmaster" \
            "$smtest" \
            "quantsort/quantsort" \
            "$smdir/../../../glue/ksortcontroller" \
            ; do
        if [ -x "$name" ]; then
            true
        else
            echo "$name doesn't exist or not executable, skipping sort master test"
            smtest=''
            break
        fi
    done

    fotest=1
    if [ -d "$fodir" ]; then
        fosdir="$sortdir/$fodir"
    else
        echo "$fodir doesn't exist skipping fanout test"
        fodir=''
        fosdir=$fodir
        fotest=0
    fi
fi

accessdir='src/cc/access'
if [ -e "$accessdir/libqfs_access."* -a -x "`which java 2>/dev/null`" ]; then
    kfsjar="`dirname "$0"`"
    kfsjarvers=`$kfsjar/../cc/common/buildversgit.sh --release`
    kfsjar="`cd "$kfsjar/../../build/java/qfs-access" >/dev/null 2>&1 && pwd`"
    kfsjar="${kfsjar}/qfs-access-${kfsjarvers}.jar"
    if [ -e "$kfsjar" ]; then
        accessdir="`cd "${accessdir}" >/dev/null 2>&1 && pwd`"
    else
        accessdir=''
    fi
else
    accessdir=''
fi

monitorpluginlib="`pwd`/`echo 'contrib/plugins/libqfs_monitor.'*`"

for dir in  \
        'src/cc/devtools' \
        'src/cc/chunk' \
        'src/cc/meta' \
        'src/cc/tools' \
        'src/cc/libclient' \
        'src/cc/kfsio' \
        'src/cc/qcdio' \
        'src/cc/common' \
        'src/cc/qcrs' \
        'src/cc/qfsc' \
        'src/cc/krb' \
        'src/cc/emulator' \
        "`dirname "$0"`" \
        "$fosdir" \
        "$fodir" \
        ; do
    if [ x"${dir}" = x ]; then
        continue;
    fi
    if [ -d "${dir}" ]; then
        dir=`cd "${dir}" >/dev/null 2>&1 && pwd`
        dname=`basename "$dir"`
        if [ x"$dname" = x'meta' ]; then
            metabindir=$dir
        elif  [ x"$dname" = x'chunk' ]; then
            chunkbindir=$dir
        fi
    fi
    if [ -d "${dir}" ]; then
        true
    else
        echo "missing directory: ${dir}"
        exit 1
    fi
    PATH="${dir}:${PATH}"
    LD_LIBRARY_PATH="${dir}:${LD_LIBRARY_PATH}"
done
# fuser might be in sbin
PATH="${PATH}:/sbin:/usr/sbin"
export PATH
export LD_LIBRARY_PATH

rm -rf "$testdir"
mkdir "$testdir" || exit
mkdir "$metasrvdir" || exit
mkdir "$chunksrvdir" || exit

cabundlefileos='/etc/pki/tls/certs/ca-bundle.crt'
cabundlefile="$chunksrvdir/ca-bundle.crt"
objectstoredir="$chunksrvdir/object_store"
cabundleurl='https://raw.githubusercontent.com/bagder/ca-bundle/master/ca-bundle.crt'
if [ x"$s3test" = x'yes' ]; then
    if [ -f "$cabundlefileos" ]; then
        echo "Using $cabundlefileos"
        cabundlefile=$cabundlefileos
    else
        if [ -x "`which curl 2>/dev/null`" ]; then
            curl "$cabundleurl" > "$cabundlefile" || exit
        else
            wget "$cabundleurl" -O "$cabundlefile" || exit
        fi
    fi
else
    mkdir "$objectstoredir" || exit
fi

if [ $fotest -ne 0 ]; then
    mindiskspace=$minrequreddiskspacefanoutsort
    lowdiskspace=$lowrequreddiskspacefanoutsort
else
    mindiskspace=$minrequreddiskspace
    lowdiskspace=$lowrequreddiskspace
fi

df -P -k "$testdir" | awk '
    BEGIN {
        msp='"${mindiskspace}"'
        scp='"${lowdiskspace}"'
    }
    {
        lns = lns $0 "\n"
    }
    /^\// {
    asp = $4 * 1024
    if (asp < msp) {
        print lns
        printf(\
            "Insufficient host file system available space:" \
            " %5.2e, at least %5.2e required for the test.\n", \
            asp, msp)
        exit 1
    }
    if (asp < scp) {
        print lns
        printf(\
            "Running tests sequentially due to low disk space:" \
            " %5.2e, at least %5.2e required to run tests concurrently.\n", \
            asp, scp)
        exit 2
    }
    }'
spacecheck=$?
if [ $spacecheck -eq 1 ]; then
    exit 1
fi

if [ x"$auth" = x'yes' ]; then
    "$mkcerts" "$certsdir" meta root "$clientuser" || exit
cat > "$clientprop" << EOF
client.auth.X509.X509PemFile = $certsdir/$clientuser.crt
client.auth.X509.PKeyPemFile = $certsdir/$clientuser.key
client.auth.X509.CAFile      = $certsdir/qfs_ca/cacert.pem
EOF
else
    cp /dev/null  "$clientprop"
fi

QFS_CLIENT_CONFIG="FILE:${clientprop}"
export QFS_CLIENT_CONFIG

ulimit -c unlimited
echo "Running RS unit test with 6 data stripes"
mytimecmd='time'
{ $mytimecmd true ; } > /dev/null 2>&1 || mytimecmd=
$mytimecmd rstest 6 65536 2>&1 || exit

# Cleanup handler
if [ x"$dontusefuser" = x'yes' ]; then
    trap 'sleep 1; kill -KILL 0' TERM
    trap 'kill -TERM 0' EXIT INT HUP
else
    trap 'cd "$testdir" && find . -type f $findprint | xargs $xargsnull fuser 2>/dev/null | xargs kill -KILL 2>/dev/null' EXIT INT HUP
fi

echo "Starting meta server $metahosturl:$metasrvport"

if [ x"$myvalgrind" = x ]; then
    csheartbeattimeout=60
    csheartbeatskippedinterval=50
    cssessionmaxtime=`expr $csheartbeatinterval + 10`
    clisessionmaxtime=5
else
    # Run test sequentially with valgrind
    if [ $spacecheck -ne 2 ]; then
        spacecheck=3
    fi
    csheartbeattimeout=900
    csheartbeatskippedinterval=800
    cssessionmaxtime=`expr $csheartbeatinterval + 50`
    clisessionmaxtime=25
    cat >> "$clientprop" << EOF
client.defaultOpTimeout=600
client.defaultMetaOpTimeout=600
EOF
fi

cd "$metasrvdir" || exit
mkdir kfscp || exit
mkdir kfslog || exit
cat > "$metasrvprop" << EOF
metaServer.clientIp = $iptobind
metaServer.chunkServerIp = $iptobind
metaServer.clientPort = $metasrvport
metaServer.chunkServerPort = $metasrvchunkport
metaServer.clusterKey = $clustername
metaServer.cpDir = kfscp
metaServer.logDir = kfslog
metaServer.chunkServer.heartbeatTimeout  = $csheartbeattimeout
metaServer.chunkServer.heartbeatInterval = $csheartbeatinterval
metaServer.chunkServer.heartbeatSkippedInterval = $csheartbeatskippedinterval
metaServer.recoveryInterval = 2
metaServer.loglevel = DEBUG
metaServer.rebalancingEnabled = 1
metaServer.allocateDebugVerify = 1
metaServer.panicOnInvalidChunk = 1
metaServer.panicOnRemoveFromPlacement = 1
metaServer.clientSM.auditLogging = 1
metaServer.auditLogWriter.logFilePrefixes = audit.log
metaServer.auditLogWriter.maxLogFileSize = 1e9
metaServer.auditLogWriter.maxLogFiles = 5
metaServer.auditLogWriter.waitMicroSec = 36000e6
metaServer.rootDirUser = `id -u`
metaServer.rootDirGroup = `id -g`
metaServer.rootDirMode = 0777
metaServer.maxSpaceUtilizationThreshold = 0.99999
metaServer.clientCSAllowClearText = $csallowcleartext
metaServer.appendPlacementIgnoreMasterSlave = 1
metaServer.clientThreadCount = 2
metaServer.startupAbortOnPanic = 1
metaServer.objectStoreEnabled  = 1
metaServer.objectStoreDeleteDelay = 2
metaServer.objectStoreReadCanUsePoxoyOnDifferentHost = 1
metaServer.objectStoreWriteCanUsePoxoyOnDifferentHost = 1
metaServer.objectStorePlacementTest = 1
metaServer.replicationCheckInterval = 0.5
metaServer.checkpoint.lockFileName = ckpt.lock
metaServer.dumpsterCleanupDelaySec = 2
EOF

if [ x"$myvalgrind" = x ]; then
    true
else
    cat >> "$metasrvprop" << EOF
metaServer.chunkServer.chunkAllocTimeout   = 500
metaServer.chunkServer.chunkReallocTimeout = 500
EOF
fi

if [ x"$auth" = x'yes' ]; then
    cat >> "$metasrvprop" << EOF
metaServer.clientAuthentication.X509.X509PemFile = $certsdir/meta.crt
metaServer.clientAuthentication.X509.PKeyPemFile = $certsdir/meta.key
metaServer.clientAuthentication.X509.CAFile      = $certsdir/qfs_ca/cacert.pem
metaServer.clientAuthentication.whiteList        = $clientuser root

# Set short valid time to test session time enforcement.
metaServer.clientAuthentication.maxAuthenticationValidTimeSec = $clisessionmaxtime
# Insure that the write lease is valid for at least 10 min to avoid spurious
# write retries with 5 seconds authentication timeous.
metaServer.minWriteLeaseTimeSec = 600

metaServer.CSAuthentication.X509.X509PemFile     = $certsdir/meta.crt
metaServer.CSAuthentication.X509.PKeyPemFile     = $certsdir/meta.key
metaServer.CSAuthentication.X509.CAFile          = $certsdir/qfs_ca/cacert.pem
metaServer.CSAuthentication.blackList            = none

# Set short valid time to test chunk server re-authentication.
metaServer.CSAuthentication.maxAuthenticationValidTimeSec = $cssessionmaxtime

metaServer.cryptoKeys.keysFileName               = keys.txt
EOF
fi

# Test meta server distributing S3 configuration to chunk servers.
if [ x"$s3test" = x'yes' ]; then
    cat >> "$metasrvprop" << EOF
chunkServer.diskQueue.aws.bucketName                 = $QFS_S3_BUCKET_NAME
chunkServer.diskQueue.aws.accessKeyId                = $QFS_S3_ACCESS_KEY_ID
chunkServer.diskQueue.aws.secretAccessKey            = $QFS_S3_SECRET_ACCESS_KEY
chunkServer.diskQueue.aws.region                     = $QFS_S3_REGION_NAME
chunkServer.diskQueue.aws.useServerSideEncryption    = $s3serversideencryption
chunkServer.diskQueue.aws.ssl.verifyPeer             = 1
chunkServer.diskQueue.aws.ssl.CAFile                 = $cabundlefile
chunkServer.diskQueue.aws.debugTrace.requestHeaders  = $s3debug
chunkServer.diskQueue.aws.debugTrace.requestProgress = $s3debug
EOF
fi

"$metabindir"/metaserver \
        -c "$metasrvprop" > "${metaservercreatefsout}" 2>&1 || {
    status=$?
    cat "${metaservercreatefsout}"
    exit $status
}

cat >> "$metasrvprop" << EOF
metaServer.csmap.unittest = 1
EOF

myrunprog "$metabindir"/metaserver \
    "$metasrvprop" "$metasrvlog" > "${metasrvout}" 2>&1 &
metapid=$!
echo "$metapid" > "$metasrvpid"

cd "$testdir" || exit
ensurerunning "$metapid" || exit
echo "Waiting for the meta server startup unit tests to complete."
if [ x"$myvalgrind" = x ]; then
    true
else
    echo "With valgrind meta server unit tests might take serveral minutes."
fi
remretry=20
until qfsshell -s "$metahost" -p "$metasrvport" -q -- stat / 1>/dev/null; do
    kill -0 "$metapid" || exit
    remretry=`expr $remretry - 1`
    [ $remretry -le 0 ] && break
    sleep 3
done

if [ x"$myvalgrind" = x ]; then
    csmetainactivitytimeout=180
else
    csmetainactivitytimeout=300
fi

i=$chunksrvport
e=`expr $i + $numchunksrv`
while [ $i -lt $e ]; do
    dir="$chunksrvdir/$i"
    mkdir "$dir" || exit
    mkdir "$dir/kfschunk" || exit
    mkdir "$dir/kfschunk-tier0" || exit
    cat > "$dir/$chunksrvprop" << EOF
chunkServer.clientIp = $iptobind
chunkServer.metaServer.hostname = $metahost
chunkServer.metaServer.port = $metasrvchunkport
chunkServer.clientPort = $i
chunkServer.clusterKey = $clustername
chunkServer.rackId = $i
chunkServer.chunkDir = kfschunk kfschunk-tier0
chunkServer.logDir = kfslog
chunkServer.diskIo.crashOnError = 1
chunkServer.abortOnChecksumMismatchFlag = 1
chunkServer.msgLogWriter.logLevel = DEBUG
chunkServer.recAppender.closeEmptyWidStateSec = 5
chunkServer.bufferManager.maxClientQuota = 4202496
chunkServer.requireChunkHeaderChecksum = 1
chunkServer.storageTierPrefixes = kfschunk-tier0 2
chunkServer.exitDebugCheck = 1
chunkServer.rsReader.debugCheckThread = 1
chunkServer.clientThreadCount = $chunkserverclithreads
chunkServer.forceVerifyDiskReadChecksum = $trdverify
chunkServer.debugTestWriteSync = $twsync
chunkServer.clientSM.traceRequestResponse   = $csrpctrace
chunkServer.remoteSync.traceRequestResponse = $csrpctrace
chunkServer.meta.traceRequestResponseFlag   = $csrpctrace
chunkServer.placementMaxWaitingAvgSecsThreshold = 600
chunkServer.maxSpaceUtilizationThreshold = 0.00001
chunkServer.meta.inactivityTimeout = $csmetainactivitytimeout
# chunkServer.forceVerifyDiskReadChecksum = 1
# chunkServer.debugTestWriteSync = 1
# chunkServer.diskQueue.trace = 1
# chunkServer.diskQueue.maxDepth = 8
# chunkServer.diskErrorSimulator.enqueueFailInterval = 5
EOF
    if [ x"$myvalgrind" = x ]; then
        true
    else
        cat >> "$dir/$chunksrvprop" << EOF
chunkServer.diskIo.maxIoTimeSec = 580
EOF
    fi
    if [ x"$auth" = x'yes' ]; then
        "$mkcerts" "$certsdir" chunk$i || exit
        cat >> "$dir/$chunksrvprop" << EOF
chunkserver.meta.auth.X509.X509PemFile = $certsdir/chunk$i.crt
chunkserver.meta.auth.X509.PKeyPemFile = $certsdir/chunk$i.key
chunkserver.meta.auth.X509.CAFile      = $certsdir/qfs_ca/cacert.pem
EOF
    fi
    if [ x"$s3test" = x'yes' ]; then
        cat >> "$dir/$chunksrvprop" << EOF
chunkServer.objectDir = s3://aws.
# Give the buffer manager the same as with no S3 8192*0.4, appender
# 8192*(1-0.4)*0.4, and the rest to S3 write buffers: 16 chunks by 10MB + 64KB
# buffer for each.
chunkServer.objStoreBufferDataRatio           = 0.8871
chunkServer.recAppender.bufferLimitRatio      = 0.0424
chunkServer.bufferManager.maxRatio            = 0.0705
chunkServer.ioBufferPool.partitionBufferCount = 46460
EOF
    else
        cat >> "$dir/$chunksrvprop" << EOF
chunkServer.ioBufferPool.partitionBufferCount = 8192
chunkServer.objStoreBlockWriteBufferSize      = $objectstorebuffersize
chunkServer.objectDir                         = $objectstoredir
EOF
    fi
    cd "$dir" || exit
    echo "Starting chunk server $i"
    myrunprog "$chunkbindir"/chunkserver \
        "$chunksrvprop" "$chunksrvlog" > "${chunksrvout}" 2>&1 &
    echo $! > "$chunksrvpid"
    i=`expr $i + 1`
done

cd "$testdir" || exit

# Ensure that chunk and meta servers are running.
for pid in `getpids`; do
    ensurerunning "$pid" || exit
done

if [ x"$auth" = x'yes' ]; then
    clientdelegation=`qfs \
        -fs "qfs://${metahosturl}:${metasrvport}" \
        -cfg "${clientprop}" -delegate | awk '
    { if ($1 == "Token:") t=$2; else if ($1 == "Key:") k=$2; }
    END{printf("client.auth.psk.key=%s client.auth.psk.keyId=%s", k, t); }'`
    clientenvcfg="${clientdelegation} client.auth.allowChunkServerClearText=0"

    cat > "$clientrootprop" << EOF
client.auth.X509.X509PemFile = $certsdir/root.crt
client.auth.X509.PKeyPemFile = $certsdir/root.key
client.auth.X509.CAFile      = $certsdir/qfs_ca/cacert.pem
EOF
else
    clientenvcfg=
    cp /dev/null "$clientrootprop"
fi
qfstoolrootauthcfg=$clientrootprop

if [ x"$myvalgrind" = x ]; then
    true
else
    cat >> "$clientrootprop" << EOF
client.defaultOpTimeout=600
client.defaultMetaOpTimeout=600
EOF
fi

echo "Waiting for chunk servers to connect to meta server."
remretry=20
until [ `qfsadmin \
            -s "$metahost" -p "$metasrvport" -f "$clientrootprop" upservers \
        | wc -l` -eq $numchunksrv ]; do
    kill -0 "$metapid" || exit
    remretry=`expr $remretry - 1`
    [ $remretry -le 0 ] && break
    sleep 1
done

if [ x"$jerasuretest" = 'x' ]; then
    if qfs -ecinfo | grep -w jerasure > /dev/null; then
        jerasuretest='yes'
    else
        jerasuretest='no'
    fi
fi

echo "Starting copy test. Test file sizes: $sizes"
# Run normal test first, then rs test.
# Enable read ahead and set buffer size to an odd value.
# For RS disable read ahead and set odd buffer size.
# Schedule meta server checkpoint after the first two tests.

if [ x"$myvalgrind" = x ]; then
    if [ x"$cptestextraopts" = x ]; then
        true
    else
        $cptestextraopts=" $cptestextraopts"
    fi
    if [ $spacecheck -ne 0 ] || uname | grep CYGWIN > /dev/null; then
        # Sleep before renaming test directories to ensure that all files
        # are closed / flushed by QFS / os
        cptestendsleeptime=3
    else
        cptestendsleeptime=0
    fi
else
    cptestextraopts=" -T 240 $cptestextraopts"
    cptestendsleeptime=5
fi

cp /dev/null cptest.out
cppidf="cptest${pidsuf}"
{
#    cptokfsopts='-W 2 -b 32767 -w 32767' && \
    QFS_CLIENT_CONFIG=$clientenvcfg \
    cptokfsopts='-r 0 -m 15 -l 15 -R 20 -w -1'"$cptestextraopts" \
    cpfromkfsopts='-r 0 -w 65537'"$cptestextraopts" \
    cptest.sh && \
    sleep $cptestendsleeptime && \
    mv cptest.log cptest-os.log && \
    cptokfsopts='-r 3 -m 1 -l 15 -w -1'"$cptestextraopts" \
    cpfromkfsopts='-r 1e6 -w 65537'"$cptestextraopts" \
    cptest.sh && \
    sleep $cptestendsleeptime && \
    mv cptest.log cptest-0.log && \
    kill -USR1 $metapid && \
    cptokfsopts='-S -m 2 -l 2 -w -1'"$cptestextraopts" \
    cpfromkfsopts='-r 0 -w 65537'"$cptestextraopts" \
    cptest.sh && \
    { \
        [ x"$jerasuretest" = x'no' ] || { \
            sleep $cptestendsleeptime && \
            mv cptest.log cptest-rs.log && \
            cptokfsopts='-u 65536 -y 10 -z 4 -r 1 -F 3 -m 2 -l 2 -w -1'"$cptestextraopts" \
            cpfromkfsopts='-r 0 -w 65537'"$cptestextraopts" \
            cptest.sh ; \
        } \
    }
} >> cptest.out 2>&1 &
cppid=$!
echo "$cppid" > "$cppidf"

qfscpidf="qfsctest${pidsuf}"
cp /dev/null test-qfsc.out
test-qfsc "$metahost:$metasrvport" 1>>test-qfsc.out 2>test-qfsc.log &
qfscpid=$!
echo "$qfscpid" > "$qfscpidf"

if [ x"$accessdir" = x ]; then
    true
else
    kfsaccesspidf="kfsaccess_test${pidsuf}"
    clientproppool="$clientprop.pool.prp"
    if [ -f "$clientprop" ]; then
        cp "$clientprop" "$clientproppool" || exit
    else
        cp /dev/null "$clientproppool" || exit
    fi
    cat >> "$clientproppool" << EOF
client.connectionPool=1
EOF
    if [ -f "$monitorpluginlib" ]; then
        cat >> "$clientproppool" << EOF
client.monitorPluginPath=$monitorpluginlib
EOF
    fi
    javatestclicfg="FILE:${clientproppool}"
    cp /dev/null kfsaccess_test.out
    QFS_CLIENT_MONITOR_LOG_DIR="$testdir/monitor_plugin" \
    QFS_CLIENT_CONFIG="$javatestclicfg" \
    java \
        -Xms800M \
        -Djava.library.path="$accessdir" \
        -classpath "$kfsjar" \
        -Dkfs.euid="`id -u`" \
        -Dkfs.egid="`id -g`" \
        com.quantcast.qfs.access.KfsTest "$metahost" "$metasrvport" \
        >> kfsaccess_test.out 2>&1 &
    kfsaccesspid=$!
    echo "$kfsaccesspid" > "$kfsaccesspidf"
fi

if [ $spacecheck -ne 0 ]; then
    waitqfscandcptests
    pausesec=`expr $csheartbeatinterval \* 2`
    echo "Pausing for tow chunk server chunk server heartbeat intervals:"\
        "$cpausesec sec. to give a chance for space update to occur."
    sleep $cpausesec
    n=0
    until df -P -k "$testdir" | awk '
    BEGIN {
        msp='"${mindiskspace}"' * .8
        n='"$n"'
    }
    /^\// {
        asp = $4 * 1024
        if (asp < msp) {
            if (0 < n) {
                printf("Wating for chunk files cleanup to occur.\n")
                printf("Disk space: %5.2e is less thatn %5.2e\n", asp, msp)
            }
            exit 1
        } else {
            exit 0
        }
    }'; do
        sleep 1
        n=`expr $n + 1`
        [ $n -le 30 ] || break
    done
fi

cp /dev/null qfs_tool-test.out
qfstoolpidf="qfstooltest${pidsuf}"
qfstoolopts='-v' \
qfstoolmeta="$metahosturl:$metasrvport" \
qfstooltrace=on \
qfstoolrootauthcfg=$qfstoolrootauthcfg \
qfs_tool-test.sh '##??##::??**??~@!#$%^&()=<>`|||' \
    1>>qfs_tool-test.out 2>qfs_tool-test.log &
qfstoolpid=$!
echo "$qfstoolpid" > "$qfstoolpidf"

if [ $fotest -ne 0 ]; then
    if [ x"$myvalgrind" = x ]; then
        foextraopts=''
    else
        foextraopts=' -c 240'
    fi
    echo "Starting fanout test. Fanout test data size: $fanouttestsize"
    fopidf="kfanout_test${pidsuf}"
    # Do two runs one with connection pool off and on.
    cp /dev/null kfanout_test.out
    for p in 0 1; do
        kfanout_test.sh \
            -coalesce 1 \
            -host "$metahost" \
            -port "$metasrvport" \
            -size "$fanouttestsize" \
            -partitions "$fanoutpartitions" \
            -read-retries 1 \
            -kfanout-extra-opts "-U $p -P 3""$foextraopts" \
            -cpfromkfs-extra-opts "$cptestextraopts" \
        || exit
    done >> kfanout_test.out 2>&1 &
    fopid=$!
    echo "$fopid" > "$fopidf"
fi

if [ x"$smtest" = x ]; then
    true
else
    if [ x"$smauthconf" = x ]; then
        true
    else
       cat > "$smauthconf" << EOF
sortmaster.auth.X509.X509PemFile = $certsdir/$clientuser.crt
sortmaster.auth.X509.PKeyPemFile = $certsdir/$clientuser.key
sortmaster.auth.X509.CAFile      = $certsdir/qfs_ca/cacert.pem
EOF
    fi
    smpidf="sortmaster_test${pidsuf}"
    echo "Starting sort master test"
    cp /dev/null sortmaster_test.out
    QFS_CLIENT_CONFIG=$clientenvcfg "$smtest" >> sortmaster_test.out 2>&1 &
    smpid=$!
    echo "$smpid" > "$smpidf"
fi

if [ $spacecheck -eq 0 ]; then
    waitqfscandcptests
fi

if [ x"$qfstoolpid" = x ]; then
    qfstoolstatus=0
else
    mytailwait $qfstoolpid qfs_tool-test.out
    qfstoolstatus=$?
    rm "$qfstoolpidf"
fi

if [ $fotest -ne 0 ]; then
    mytailwait $fopid kfanout_test.out
    fostatus=$?
    rm "$fopidf"
else
    fostatus=0
fi

if [ x"$smtest" = x ]; then
    smstatus=0
else
    mytailwait $smpid sortmaster_test.out
    smstatus=$?
    rm "$smpidf"
fi

cd "$metasrvdir" || exit
echo "Running online fsck"
qfsfsck -s "$metahost" -p "$metasrvport" -f "$clientrootprop"
fsckstatus=$?

status=0

cd "$testdir" || exit

# For now pause to let chunk server IOs complete
sleep 5
echo "Shutting down"
pids=`getpids`
for pid in $pids; do
    kill -QUIT "$pid" || exit
done

# Wait 30 sec for shutdown to complete
nsecwait=30
i=0
while true; do
    rpids=
    for pid in $pids; do
        if kill -O "$pid" 2>/dev/null; then
            rpids="$rpids $pid"
        elif [ x"$kfstestnoshutdownwait" = x ]; then
            wait "$pid"
            estatus=$?
            if [ $estatus -ne 0 ]; then
                echo "Exit status: $estatus pid: $pid"
                status=$estatus;
            fi
        fi
    done
    pids=$rpids
    [ x"$pids" = x ] && break
    i=`expr $i + 1`
    if [ $i -le $nsecwait ]; then
        sleep 1
    else
        echo "Wait timed out, sending abort singnal to: $rpids"
        kill -ABRT $rpids
        status=1
        break
    fi
done

if [ $status -ne 0 ]; then
    showpids
fi

if [ x"$mytailpids" = x ]; then
    true
else
    # Let tail -f poll complete, then shut them down.
    { sleep 1 ; kill -TERM $mytailpids ; } &
    wait 2>/dev/null
fi

if [ $status -eq 0 ]; then
    cd "$metasrvdir" || exit
    echo "Running meta server log compactor"
    logcompactor -T newlog -C newcp
    status=$?
fi
if [ $status -eq 0 ]; then
    cd "$metasrvdir" || exit
    echo "Running meta server fsck"
    qfsfsck -c kfscp -F
    status=$?
    # Status 1 might be returned in the case if chunk servers disconnects
    # were commited, do run whout the last log segment, the disconnects
    # should be in the last one.
    if [ $status -eq 1 ]; then
        newcpfsckopt=''
    else
        newcpfsckopt='-F'
    fi
    if [ $status -le 1 ]; then
        qfsfsck -c kfscp -A 0 -F
        status=$?
    fi
fi
if [ $status -eq 0 ]; then
    qfsfsck -c newcp $newcpfsckopt
    status=$?
fi
if [ $status -eq 0 ] && [ -d "$objectstoredir" ]; then
    echo "Running meta server object store fsck"
    ls -1 "$objectstoredir" | qfsobjstorefsck
    status=$?
fi
if [ $status -eq 0 ]; then
    echo "Running re-balance planner"
    rebalanceplanner -d -L ERROR
    status=$?
fi

find "$testdir" -name core\* || status=1

if [ $status -eq 0 \
        -a $cpstatus -eq 0 \
        -a $qfstoolstatus -eq 0 \
        -a $fostatus -eq 0 \
        -a $smstatus -eq 0 \
        -a $kfsaccessstatus -eq 0 \
        -a $qfscstatus -eq 0 \
        -a $fsckstatus -eq 0 \
        ]; then
    echo "Passed all tests"
else
    echo "Test failure"
    status=1
fi

if [ x"$dontusefuser" = x'yes' ]; then
    trap '' EXIT
fi
exit $status
