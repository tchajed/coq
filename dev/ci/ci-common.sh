#!/usr/bin/env bash

set -xe

# Coq's tools need an ending slash :S, we should fix them.
export COQBIN=`pwd`/bin/
export PATH=`pwd`/bin:$PATH

ls `pwd`/bin

# Where we clone and build external developments
CI_BUILD_DIR=`pwd`/_build_ci

source ${ci_dir}/ci-user-overlay.sh
source ${ci_dir}/ci-basic-overlay.sh

mathcomp_CI_DIR=${CI_BUILD_DIR}/math-comp

# git_checkout branch url dest will create a git repository
# in <dest> (if it does not exist already) and checkout the
# remote branch <branch> from <url>
git_checkout()
{
  local _BRANCH=${1}
  local _URL=${2}
  local _DEST=${3}

  mkdir -p ${_DEST}
  ( cd ${_DEST}                                                && \
    if [ ! -d .git ] ; then git clone --depth 1 ${_URL} . ; fi && \
    echo "Checking out ${_DEST}"                               && \
    git fetch ${_URL} ${_BRANCH}                               && \
    git checkout FETCH_HEAD                                    && \
    echo "${_DEST}: `git log -1 --format='%s | %H | %cd | %aN'`" )
}

checkout_mathcomp()
{
  git_checkout ${mathcomp_CI_BRANCH} ${mathcomp_CI_GITURL} ${1}
}

# this installs just the ssreflect library of math-comp
install_ssreflect()
{
  echo 'Installing ssreflect' && echo -en 'travis_fold:start:ssr.install\\r'

  checkout_mathcomp ${mathcomp_CI_DIR}
  ( cd ${mathcomp_CI_DIR}/mathcomp   && \
    sed -i.bak '/ssrtest/d'     Make && \
    sed -i.bak '/odd_order/d'   Make && \
    sed -i.bak '/all\/all.v/d'  Make && \
    sed -i.bak '/character/d'   Make && \
    sed -i.bak '/real_closed/d' Make && \
    sed -i.bak '/solvable/d'    Make && \
    sed -i.bak '/field/d'       Make && \
    sed -i.bak '/fingroup/d'    Make && \
    sed -i.bak '/algebra/d'     Make && \
    make Makefile.coq && make -f Makefile.coq -j ${NJOBS} all && make install )

  echo -en 'travis_fold:end:ssr.install\\r'

}
