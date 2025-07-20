#!/bin/bash
# script_fuzz_py_final.sh
# 执行OSS-Fuzz本地测试全流程：自动发现目标 -> 构建镜像 -> 编译fuzzer -> 运行测试 -> 生成覆盖率报告
# 用法：script_fuzz_py_final.sh <项目名> [sanitizer类型]

set -e  # 遇到错误立即退出

PROJECT_NAME="${1:-abseil-py}"      # 默认项目名
SANITIZER="${2:-address}"           # 默认检测器类型
OSS_FUZZ_DIR="$HOME/oss-fuzz-py/oss-fuzz"        # OSS-Fuzz目录
LOG_DIR="$OSS_FUZZ_DIR/script_lz4_logs"
LOG_FILE="$LOG_DIR/oss_fuzz_${PROJECT_NAME}_$(date +%Y%m%d%H%M%S).log"
# 验证目录有效性
check_environment() {
  if [ ! -d "$OSS_FUZZ_DIR" ]; then
    echo "❌ 错误: $OSS_FUZZ_DIR 目录不存在！"
    exit 1
  fi
  mkdir -p "$LOG_DIR"  # 关键修复：创建日志目录
  chmod 777 "$LOG_DIR" 2>/dev/null || true  # 宽松权限设置
  cd "$OSS_FUZZ_DIR" || exit 1
}

# 带日志记录的命令执行（支持允许的退出码）
run_command() {
  local cmd="$1"
  local log_msg="$2"
  local allowed_exit="${3:-}"  # 可选：允许的退出码（逗号分隔）
  
  echo "▶️ $log_msg..." | tee -a "$LOG_FILE"
  set +e  # 临时禁用错误退出
  eval "$cmd" 2>&1 | tee -a "$LOG_FILE"
  local exit_code=${PIPESTATUS[0]}
  set -e  # 重新启用错误退出
  
  # 检查退出码是否被允许
  if [[ -n "$allowed_exit" && ",$allowed_exit," =~ ",$exit_code," ]]; then
    echo "ℹ️ 命令以预期状态退出: $exit_code" | tee -a "$LOG_FILE"
    return 0
  elif [ $exit_code -ne 0 ]; then
    echo "❌ 命令执行失败: $cmd (退出码: $exit_code)" | tee -a "$LOG_FILE"
    exit 1
  fi
}

# 自动发现fuzz目标
discover_fuzz_targets() {
   local project_dir="$OSS_FUZZ_DIR/build/out/$PROJECT_NAME"
    local project_src="$OSS_FUZZ_DIR/projects/$PROJECT_NAME"
    local targets=()

    # 编译目录扫描：仅匹配"fuzz_"开头的可执行文件
    if [ -d "$project_dir" ]; then
        while IFS= read -r -d $'\0' file; do
            filename=$(basename "$file")
            if [[ -x "$file" && "$filename" =~ ^fuzz_ && ! "$file" =~ \..*$ ]]; then
                targets+=("$filename")
            fi
        done < <(find "$project_dir" -maxdepth 1 -type f -print0)
    fi

    # 源码目录扫描：仅匹配"fuzz_*.py"且含Atheris标识
    if [ ${#targets[@]} -eq 0 ] && [ -d "$project_src" ]; then
        while IFS= read -r -d $'\0' file; do
            if grep -q "atheris.Setup" "$file"; then
                targets+=("$(basename "${file%.*}")")
            fi
        done < <(find "$project_src" -name 'fuzz_*.py' -print0)
    fi

    echo "${targets[@]}"
}

# 主流程
main() {
  check_environment
  echo "=============================="
  echo "🚀 开始OSS-Fuzz测试 - 项目: $PROJECT_NAME"
  echo "📝 日志文件: $LOG_FILE"
  echo "=============================="

  #1. 构建Docker镜像
  run_command \
    "python3 infra/helper.py build_image $PROJECT_NAME" \
    "步骤1/5: 构建Docker镜像"

  # 2. 编译带检测器的fuzzer
  run_command \
    "python3 infra/helper.py build_fuzzers --sanitizer $SANITIZER $PROJECT_NAME" \
    "步骤2/5: 编译fuzzer (sanitizer=$SANITIZER)"

  # 3. 自动发现目标
  echo "🔍 自动发现fuzz目标..."
  FUZZ_TARGETS=($(discover_fuzz_targets))
  
  if [ ${#FUZZ_TARGETS[@]} -eq 0 ]; then
    echo "❌ 未找到任何fuzz目标！检查项目配置" | tee -a "$LOG_FILE"
    exit 1
  fi

  echo "✅ 发现目标: ${FUZZ_TARGETS[*]}" | tee -a "$LOG_FILE"

  # 4. 遍历运行所有目标
  for target in "${FUZZ_TARGETS[@]}"; do
    run_command \
      "python3 infra/helper.py run_fuzzer $PROJECT_NAME $target -- -max_total_time=180" \
      "步骤3/5: 运行目标 [$target] (120秒超时)" \
      "124,1"  # 允许超时(124)和发现崩溃(1)
done

  # 5. 生成覆盖率报告
  # run_command \
  #   "python3 infra/helper.py build_fuzzers --sanitizer coverage $PROJECT_NAME" \
  #   "步骤4/5: 编译覆盖率版本"
  
  # run_command \
  #   "python3 infra/helper.py coverage --no-serve $PROJECT_NAME" \
  #   "步骤5/5: 生成覆盖率报告"

  echo "✅ 所有步骤完成！结果查看:"
  echo "🔍 测试日志: $LOG_FILE"
  echo "📊 覆盖率报告(暂无): $OSS_FUZZ_DIR/build/out/$PROJECT_NAME/report/coverage/index.html"
  echo "💥 崩溃报告: $OSS_FUZZ_DIR/build/out/$PROJECT_NAME/crashes/"
}

main "$@"