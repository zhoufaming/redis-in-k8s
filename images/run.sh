#!/bin/bash

# Copyright 2014 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

function launchmaster() {
  if [[ ! -e /data/redis/master ]]; then
    echo "Redis master data doesn't exist, creating dictionary!"
    mkdir -p /data/redis/master
  fi
  redis-server /config/redis/master.conf --protected-mode no
}

function launchsentinel() {
  echo "redis master ip is : " ${MASTER_IP}
  echo "redis master port is : " ${MASTER_PORT}
  echo "redis sentinel ip is : " ${SENTINEL_IP}
  echo "redis sentinel port is : " ${SENTINEL_PORT}
  while true; do
    master=$(redis-cli -h ${SENTINEL_IP} -p ${SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
    if [[ -n ${master} ]] && [[ ${master} != "ERROR" ]] ; then
      master="${master//\"}"
    else
      echo "could not find sentinel nodes. direct to master node"
      master="${MASTER_IP}"
	  master=$(nslookup ${MASTER_IP}} | grep 'Address' | awk '{print $3}')
      # master=$(hostname -i)
    fi

    redis-cli -h ${master} -p ${MASTER_PORT} INFO
    if [[ "$?" == "0" ]]; then
      break
    fi
    echo "Connecting to master failed.  Waiting..."
    sleep 10
  done

  sentinel_conf=/config/redis/sentinel.conf
  
  echo "port 6381" > ${sentinel_conf}
  echo "sentinel monitor mymaster ${master} ${MASTER_PORT} 2" >> ${sentinel_conf}
  echo "sentinel down-after-milliseconds mymaster 60000" >> ${sentinel_conf}
  echo "sentinel failover-timeout mymaster 180000" >> ${sentinel_conf}
  echo "sentinel parallel-syncs mymaster 1" >> ${sentinel_conf}
  echo "bind 0.0.0.0" >> ${sentinel_conf}

  redis-sentinel ${sentinel_conf} --protected-mode no
}

function launchslave() {
  echo "redis master ip is : " ${MASTER_IP}
  echo "redis master port is : " ${MASTER_PORT}
  echo "redis sentinel ip is : " ${SENTINEL_IP}
  echo "redis sentinel port is : " ${SENTINEL_PORT}

  if [[ ! -e /data/redis/slave ]]; then
    echo "Redis slave data doesn't exist, creating dictionary!"
    mkdir -p /data/redis/slave
  fi

  while true; do
    master=$(redis-cli -h ${SENTINEL_IP} -p ${SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
   	if [[ -n ${master} ]] && [[ ${master} != "ERROR" ]] ; then
      master="${master//\"}"
    else
      echo "could not find sentinel nodes. direct to master node"
      master="${MASTER_IP}"
      # master=$(hostname -i)
    fi
    redis-cli -h ${master} -p ${MASTER_PORT} INFO
    if [[ "$?" == "0" ]]; then
      break
    fi
    echo "Connecting to master failed.  Waiting..."
    sleep 10
  done
  sed -i "s/%master-ip%/${master}/" /config/redis/slave.conf
  sed -i "s/%master-port%/${MASTER_PORT}/" /config/redis/slave.conf
  redis-server  /config/redis/slave.conf --protected-mode no
}

if [[ "${MASTER}" == "true" ]]; then
  launchmaster
  exit 0
fi

if [[ "${SENTINEL}" == "true" ]]; then
  launchsentinel
  exit 0
fi

launchslave
