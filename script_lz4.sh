#!/bin/bash
# oss-fuzz-local-runner.sh
# 执行OSS-Fuzz本地测试全流程：构建镜像 -> 编译fuzzer -> 运行测试 -> 生成覆盖率报告
# 用法：./script_lz4.sh <项目名> <fuzzer目标名> [sanitizer类型]

set -e  # 遇到错误立即退出

PROJECT_NAME="${1:-abseil-py}"      # 默认项目名
FUZZ_TARGET="${2:-fuzz_argparse}"         # 默认fuzzer名称
SANITIZER="${3:-address}"            # 默认检测器类型
OSS_FUZZ_DIR="$HOME/oss-fuzz-py/oss-fuzz"        # OSS-Fuzz目录
LOG_FILE="oss_fuzz_${PROJECT_NAME}_$(date +%Y%m%d%H%M%S).log"

# 验证目录有效性
check_environment() {
  if [ ! -d "$OSS_FUZZ_DIR" ]; then
    echo "❌ 错误: $OSS_FUZZ_DIR 目录不存在！"
    exit 1
  fi
  cd "$OSS_FUZZ_DIR" || exit 1
}

# 带日志记录的命令执行
run_command() {
  local cmd="$1"
  local log_msg="$2"
  echo "▶️ $log_msg..." | tee -a "$LOG_FILE"
  if ! eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
    echo "❌ 命令执行失败: $cmd" | tee -a "$LOG_FILE"
    exit 1
  fi
}

# 主流程
main() {
  check_environment
  echo "=============================="
  echo "🚀 开始OSS-Fuzz测试 - 项目: $PROJECT_NAME"
  echo "📁 工作目录: $(pwd)"
  echo "📝 日志文件: $LOG_FILE"
  echo "=============================="

  # 1. 构建Docker镜像
  run_command \
    "python3 infra/helper.py build_image $PROJECT_NAME" \
    "步骤1/4: 构建Docker镜像 [$PROJECT_NAME]"

  # 2. 编译带检测器的fuzzer
  run_command \
    "python3 infra/helper.py build_fuzzers --sanitizer $SANITIZER $PROJECT_NAME" \
    "步骤2/4: 编译fuzzer [$FUZZ_TARGET] (sanitizer=$SANITIZER)"

  # 3. 运行模糊测试
  run_command \
    "python3 infra/helper.py run_fuzzer $PROJECT_NAME $FUZZ_TARGET" \
    "步骤3/4: 运行模糊测试 [$FUZZ_TARGET] (5分钟)"

  # 4. 生成覆盖率报告（分为两个独立步骤）
  run_command \
    "python3 infra/helper.py build_fuzzers --sanitizer coverage $PROJECT_NAME" \
    "步骤4/4: 编译覆盖率fuzzers"

  run_command \
    "python3 infra/helper.py coverage --no-serve $PROJECT_NAME" \
    "步骤4/4: 生成覆盖率报告"

  echo "✅ 所有步骤完成！结果查看:"
  echo "🔍 测试日志: $LOG_FILE"
  echo "📊 覆盖率报告: $OSS_FUZZ_DIR/build/out/$PROJECT_NAME/report/coverage/index.html"
}

main "$@"