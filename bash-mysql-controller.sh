#!/bin/bash
#
# @(#) mysql-bash.sh ver.1.0.0 2015.05.15
#
# Description:
#   bashからmysqlを操作するシェルスクリプトです
#
# Usage:
#   現在の設定を表示する
#   myc
#
#   Databaseを参照し設定する
#   myd
#     param1 [...] - egrepによる絞込を行います
#
#   Databaseのtebleを参照しtableを設定する
#   myt
#     param1 [...] - egrepによる絞込を行います
#
#   myw
#     param1 [...] - id=1 -> where id=1 , id=%1% -> where id like  %1%
#     param1 [...] - -id=1 -> where id!=1 , -id=%1% -> where not like  %1%
#   mywhere
#     param1 [...] - order by id limit 1

#
#   DatabaseのOPTIONを設定する
#   myo
#     param1 [...] - o=id -> ORDER BY id , l=1 -> LIMIT 1
#   myoption
#     param1 [...] - order by id limit 1
#
#   SELECT文の発行
#   mys
#     param1 [...] - egrepによる絞込を行います
#
#     tips)
#       複数の行を取得した場合 => 'foo|bar'
#
#  FETURE
#     ワンライナーで書いた場合の出力制御
#     where の大なり小なり対応
#     join実装
#     関数ごとにシェルスクリプトへ分割
#     件数が多い場合半強制的にlimit処理
#     historyからの再実行の実装
#     ステータス確認系コマンドの充足
#
###########################################################################

# 各コマンドの割り当て
alias myd='mysql-database'
alias myt='mysql-table'
alias myc='mysql-config'
alias mycc='mysql-config-detail'
alias mys='mysql-select'
alias myw='mysql-where-dsl'
alias myo='mysql-option-dsl'
alias myh='mysql-query-history'

alias mywhere='mysql-where'
alias myoption='mysql-option'
alias mye='mysql-exec'

# クエリログの出力先
export PATH_MYSQL_QUERY_HISTORY
PATH_MYSQL_QUERY_HISTORY='/tmp/mysql-query.history'

red=31
green=32
yellow=33
blue=34

mysql-config() {
  if [ "$MYSQL_DB" == "" ]; then
    echo-color -e $red "DBが未設定です"
    return 2>&- || exit
  fi

  echo-color -e $green "db     :" $MYSQL_DB
  if [ "$MYSQL_TABLE" != "" ]; then
  echo-color -e $green "table  :" $MYSQL_TABLE
  fi
}


mysql-config-detail() {
  local last_query=`mysql-query-history |tail -1`
  mysql-config

  if [ "$MYSQL_TABLE" != "" ]; then
  mysql-desc-exec
  echo "row    :" $MYSQL_TABLE_RECODE_NUM
  echo "where  :" $MYSQL_WHERE
  echo "option :" $MYSQL_OPTION
  fi
  echo ""
  echo "last query:" "$last_query"
}

mysql-exec() {
  local command=$*
  echo "$command" >> $PATH_MYSQL_QUERY_HISTORY
  MYSQL_QUERY=("${MYSQL_QUERY[@]}" "$command")
  mysql -e "$command"
}

mysql-query-history() {
  local command="tail -10 ${PATH_MYSQL_QUERY_HISTORY}"
  local tail_log=`eval "$command"`
  local command="echo -e '${tail_log}' > ${PATH_MYSQL_QUERY_HISTORY}"
  `eval "$command"`
  cat "${PATH_MYSQL_QUERY_HISTORY}"
}

mysql-database() {
  local sql="show databases"
  local sql_result=`mysql-exec ${sql}`

  local opt=`chain-egrep $@`
  local command="echo -e '${sql_result}' |egrep -v Database ${opt}"
  local grep_result=`eval "$command"`

  if [ "${grep_result}" == "" ]; then
    echo "grep : $opt"
    echo-color -e $red "対象のDBがありませんでした"
    return 2>&- || exit
  fi

  MYSQL_DB=`echo -e "$grep_result" |head -1`
  unset MYSQL_TABLE
  MYSQL_WHERE='1=1'
  MYSQL_OPTION=''
  unset MYSQL_DESC

  echo-color -ne $green "db     : "
  echo "-e" "${grep_result}"
}

mysql-table() {
  if [ "$MYSQL_DB" == "" ]; then
    echo-color -e $red 'DBが未設定です'
    return 2>&- || exit
  fi

  local sql="show tables from ${MYSQL_DB}"
  local sql_result=`mysql-exec ${sql}`
  local opt=`chain-egrep $@`
  local command="echo -e '${sql_result}' |egrep -v Tables_in ${opt}"
  local grep_result=`eval "$command"`

  if [ "${grep_result}" == "" ]; then
    echo "db   : ${MYSQL_DB}"
    echo "grep : $opt"
    echo-color -e $red "対象のテーブルがありませんでした"
    return 2>&- || exit
  fi

  MYSQL_TABLE=`echo -e "$grep_result" |head -1`
  MYSQL_TABLE_RECODE_NUM=`mysql-recode-count-exec`
  MYSQL_DESC=`mysql-desc-exec`

  echo-color -ne $green "table  : "
  echo "-e" "${grep_result}"
}

mysql-desc-exec() {
  mysql -e "DESC ${MYSQL_DB}.${MYSQL_TABLE}"
}

mysql-recode-count-exec() {
  mysql -e "select count(*) from ${MYSQL_DB}.${MYSQL_TABLE}" |tail -1
}

mysql-select() {
  if [ "$MYSQL_DB" == "" ]; then
    echo-color -e $red 'DBが未設定です'
    return 2>&- || exit
  fi

  if [ "$MYSQL_TABLE" == "" ]; then
    echo-color -e $red 'テーブルが未設定です'
    return 2>&- || exit
  fi

  local sql="select * from ${MYSQL_DB}.${MYSQL_TABLE} where ${MYSQL_WHERE} ${MYSQL_OPTION}\G"
  local sql_result=`mysql-exec "${sql}"`
  #MYSQL_QUERY=("${MYSQL_QUERY[@]}" "$sql")

  if [ "${sql_result}" = "" ]; then
    echo "$sql"
    echo-color -e $red "0件"
    return 2>&- || exit
  fi

  local opt=`chain-egrep $@`
  local command="echo -e '${sql_result}' ${opt}"
  local result=`eval "$command"`

  echo -e "$result"
}

mysql-where-dsl() {
  local opt="1=1"
  for i in $@; do
    local search=`printf "%s" $i|cut -d "=" -f2`

    local _h=`printf "%s" $i|cut -c 1-1`
    if [ "${_h}" == "-" ]; then
      local equal_or_like=`mysql-where-not-equal-or-like ${search}`;
      local i=`printf "%s" $i|cut -c 2-`
    else
      local equal_or_like=`mysql-where-equal-or-like ${search}`;
    fi

    local _field=`printf "%s" $i|cut -d "=" -f1`

    # 複数あった場合の挙動
    local command="mysql-desc-exec |awk '{print \$1}'|egrep ${_field}|cut -f1"
    local hit_field=`eval "$command"`

    if [ "${hit_field}" == "" ]; then
      mysql-desc-exec
      echo "${_field} : フィールドがありません"
      return 2>&- || exit
    fi

    # 該当するフィールド数を取得
    local command="echo -e '${hit_field}' |egrep . |wc -l|xargs echo "
    local res_num=`eval "$command"`
    if [ "${res_num}" -eq "1" ]; then
      if [ "${search}" == "NULL" ]; then
        local isnull_or_null=`mysql-where-null ${_h}`;
        local opt="${opt} AND ${hit_field} ${isnull_or_null} NULL"
      else
        local opt="${opt} AND ${hit_field} ${equal_or_like} '${search}'"
      fi
    else
      echo -e "${_field} :${res_num} 件のフィールドがあります"
      echo "----------"
      echo "$hit_field"
      echo "----------"
    fi
  done
  echo "where : ${opt}"
  MYSQL_WHERE=${opt}
}

mysql-where() {
  echo "where : ${*}"
  MYSQL_WHERE="${*}"
}

mysql-where-null(){
  [  "$1" = "-" ] && echo "IS NOT" || echo "IS"
}

mysql-where-not-equal-or-like(){
  [ `echo $1|grep %` ] && echo "NOT LIKE" || echo "!="
}

mysql-where-equal-or-like(){
  [ `echo $1|grep %` ] && echo "LIKE" || echo "="
}

mysql-option-dsl() {
local _asc_or_desc=""
local order=""
local limit=""
  for i in $@; do
    local value=`printf "%s" $i|cut -d "=" -f2`
    local key=`printf "%s" $i|cut -d "=" -f1`

    local _h1=`printf "%s" $i|cut -c 1-1`
    local _h2=`printf "%s" $i|cut -c 1-2`
    if [ "${_h2}" == "oa" -o "${key}" == "orderasc" ]; then
      local _asc_or_desc="ASC"
    elif [ "${_h2}" == "od" -o "${key}" == "orderdesc" ]; then
      local _asc_or_desc="DESC"
    elif [ "${_h1}" == "o" ]; then
      local _asc_or_desc="ASC"
    elif [ "${_h1}" == "l" ]; then
      local limit="LIMIT ${value}"
    else
      echo -e "${key} : 存在しません"
      echo "Usage )"
      echo "LIMIT=1          => limit=1      or l=1"
      echo "LIMIT=1,1        => limit=1,1    or l=1,1"
      echo "ORDER BY id      => order=id     or o=id"
      echo "ORDER BY id ASC  => orderasc=id  or oa=id"
      echo "ORDER BY id DESC => orderdesc=id or od=id"
      echo "----------"
    fi

    if [ "${_asc_or_desc}" != "" ]; then
      # [TODO] hseki 
      local command="mysql-desc-exec |awk '{print \$1}'|egrep ${value}|cut -f1"
      local hit_field=`eval "$command"`

      if [ "${hit_field}" == "" ]; then
        mysql-desc-exec
        echo "${value} : フィールドがありません"
        return 2>&- || exit
      fi
      local order="ORDER BY ${hit_field} ${_asc_or_desc}"
      local _asc_or_desc=""
    fi

  done
  echo "option : ${order} ${limit}"
  MYSQL_OPTION="${order} ${limit}"
}

mysql-option() {
  echo "option : ${*}"
  MYSQL_OPTION="${*}"
}

chain-egrep(){
  local opt=""
  for i in $@; do
    local h=`printf "%s" $i|cut -c 1-1`
    if [ "${h}" = "-" ]; then
      local i=`printf "%s" $i|cut -c 2-`
      local opt="$opt|egrep -v '${i}'"
    else
      local opt="$opt|egrep '${i}'"
    fi
  done
  echo ${opt}
}

echo-color() {
local option=$1
shift
local color=$1
shift

local color_start="\033[${color}m"
local color_end="\033[m"

echo "${option}" "${color_start}$@${color_end}"
}
