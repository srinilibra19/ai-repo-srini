#!/bin/sh
# ----------------------------------------------------------------------------
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# Apache Maven Wrapper startup script, version 3.3.2
# ----------------------------------------------------------------------------

# If JAVA_HOME is not set, try to find it.
if [ -z "$JAVA_HOME" ] ; then
  JAVACMD=$(command -v java)
  if [ -z "$JAVACMD" ] ; then
    echo "Error: JAVA_HOME is not set and no 'java' command could be found in your PATH." >&2
    exit 1
  fi
else
  JAVACMD="$JAVA_HOME/bin/java"
fi

# Locate the script directory.
APP_HOME=$(cd "$(dirname "$0")" && pwd)
WRAPPER_JAR="$APP_HOME/.mvn/wrapper/maven-wrapper.jar"
WRAPPER_PROPERTIES="$APP_HOME/.mvn/wrapper/maven-wrapper.properties"

# Download the wrapper jar if it doesn't exist.
if [ ! -f "$WRAPPER_JAR" ] ; then
  if [ -f "$WRAPPER_PROPERTIES" ] ; then
    WRAPPER_URL=$(grep wrapperUrl "$WRAPPER_PROPERTIES" | cut -d= -f2-)
    echo "Downloading: $WRAPPER_URL"
    curl -sL -o "$WRAPPER_JAR" "$WRAPPER_URL" || {
      echo "Could not download $WRAPPER_URL" >&2; exit 1;
    }
  fi
fi

exec "$JAVACMD" \
  -classpath "$WRAPPER_JAR" \
  "-Dmaven.multiModuleProjectDirectory=$APP_HOME" \
  org.apache.maven.wrapper.MavenWrapperMain "$@"
