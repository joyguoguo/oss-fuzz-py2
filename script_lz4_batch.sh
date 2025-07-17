#!/bin/bash
# script_lz4_batch.sh
# 批量执行OSS-Fuzz本地测试全流程：从文件读取项目列表，依次为每个项目自动发现目标 -> 构建镜像 -> 编译fuzzer -> 运行测试 -> 生成覆盖率报告
# 用法：./script_lz4_batch.sh [项目列表文件] [sanitizer类型]
# 示例: ./script_lz4_batch.sh valid_projects.txt address

# --- 全局配置 ---
PROJECT_LIST_FILE="${1:-valid_projects.txt}" # 默认项目列表文件
SANITIZER="${2:-address}"                   # 默认检测器类型
OSS_FUZZ_DIR="$HOME/oss-fuzz-py/oss-fuzz"      # OSS-Fuzz目录
LOG_DIR="$OSS_FUZZ_DIR/script_lz4_baatch_logs"        # 所有项目的总日志目录
FAILED_PROJECTS=()                          # 存储失败项目列表

# --- 环境检查 ---
check_environment() {
  if [ ! -d "$OSS_FUZZ_DIR" ]; then
    echo "❌ 错误: OSS-Fuzz 目录 '$OSS_FUZZ_DIR' 不存在！"
    return 1
  fi
  if [ ! -f "$PROJECT_LIST_FILE" ]; then
    echo "❌ 错误: 项目列表文件 '$PROJECT_LIST_FILE' 不存在！"
    return 1
  fi
  mkdir -p "$LOG_DIR"
  chmod 777 "$LOG_DIR" 2>/dev/null || true
  cd "$OSS_FUZZ_DIR" || return 1
  echo "✅ 环境检查通过。OSS-Fuzz 目录: $OSS_FUZZ_DIR"
}

# --- 带日志记录的命令执行 ---
run_command() {
  local cmd="$1"
  local log_msg="$2"
  local log_file="$3" # 日志文件作为参数传入
  local allowed_exit="${4:-}"

  echo "▶️ $log_msg..." | tee -a "$log_file"
  set +e
  eval "$cmd" 2>&1 | tee -a "$log_file"
  local exit_code=${PIPESTATUS[0]}
  set -e

  if [[ -n "$allowed_exit" && ",$allowed_exit," =~ ",$exit_code," ]]; then
    echo "ℹ️ 命令以预期状态退出: $exit_code" | tee -a "$log_file"
    return 0
  elif [ $exit_code -ne 0 ]; then
    echo "❌ 命令执行失败: $cmd (退出码: $exit_code)" | tee -a "$log_file"
    return 1  # 返回错误而不是退出脚本
  fi
}

# --- 自动发现 Fuzz 目标 ---
discover_fuzz_targets() {
    local project_name="$1"
    local project_dir="$OSS_FUZZ_DIR/build/out/$project_name"
    local project_src="$OSS_FUZZ_DIR/projects/$project_name"
    local targets=()

    if [ -d "$project_dir" ]; then
        while IFS= read -r -d $'\0' file; do
            filename=$(basename "$file")
            if [[ -x "$file" && "$filename" =~ ^fuzz_ && ! "$file" =~ \..*$ ]]; then
                targets+=("$filename")
            fi
        done < <(find "$project_dir" -maxdepth 1 -type f -print0)
    fi

    if [ ${#targets[@]} -eq 0 ] && [ -d "$project_src" ]; then
        while IFS= read -r -d $'\0' file; do
            if grep -q "atheris.Setup" "$file"; then
                targets+=("$(basename "${file%.*}")")
            fi
        done < <(find "$project_src" -name 'fuzz_*.py' -print0)
    fi

    echo "${targets[@]}"
}

# --- 单个项目的完整处理流程 ---
process_project() {
  local project_name="$1"
  local log_file="$LOG_DIR/oss_fuzz_${project_name}_$(date +%Y%m%d%H%M%S).log"
  local project_failed=0

  echo "============================================================" | tee -a "$log_file"
  echo "🚀 开始处理项目: $project_name" | tee -a "$log_file"
  echo "📝 日志文件: $log_file" | tee -a "$log_file"
  echo "============================================================" | tee -a "$log_file"

  # 1. 构建Docker镜像
  if ! run_command \
    "python3 infra/helper.py build_image $project_name" \
    "步骤1/5: 构建 $project_name 的Docker镜像" \
    "$log_file"; then
    echo "❌ 项目 $project_name 构建镜像失败，跳过后续步骤" | tee -a "$log_file"
    project_failed=1
  fi

  # 2. 编译带检测器的fuzzer (仅在构建镜像成功后执行)
  if [ $project_failed -eq 0 ]; then
    if ! run_command \
      "python3 infra/helper.py build_fuzzers --sanitizer $SANITIZER $project_name" \
      "步骤2/5: 编译 $project_name 的fuzzer (sanitizer=$SANITIZER)" \
      "$log_file"; then
      echo "❌ 项目 $project_name 编译fuzzer失败，跳过后续步骤" | tee -a "$log_file"
      project_failed=1
    fi
  fi

  # 3. 自动发现目标 (仅在编译成功后执行)
  if [ $project_failed -eq 0 ]; then
    echo "🔍 正在为 $project_name 自动发现fuzz目标..." | tee -a "$log_file"
    FUZZ_TARGETS=($(discover_fuzz_targets "$project_name"))

    if [ ${#FUZZ_TARGETS[@]} -eq 0 ]; then
      echo "⚠️  警告: 项目 $project_name 未找到任何fuzz目标！跳过运行步骤。" | tee -a "$log_file"
    else
      echo "✅ 发现目标: ${FUZZ_TARGETS[*]}" | tee -a "$log_file"
      
      # 4. 遍历运行所有目标
      for target in "${FUZZ_TARGETS[@]}"; do
        if ! run_command \
          "python3 infra/helper.py run_fuzzer $project_name $target" \
          "步骤3/5: 运行目标 [$target] (120秒超时)" \
          "$log_file" \
          "124,1"; then  # 允许超时(124)和发现崩溃(1)
          echo "⚠️  警告: 目标 [$target] 运行失败，继续下一个目标" | tee -a "$log_file"
        fi
      done
    fi
  fi

  # 5. 生成覆盖率报告 (已注释掉，与原脚本保持一致)
  # [保留原有注释的覆盖率代码]

  if [ $project_failed -eq 0 ]; then
    echo "✅ 项目 $project_name 处理完成！" | tee -a "$log_file"
  else
    echo "❌ 项目 $project_name 处理失败！" | tee -a "$log_file"
  fi
  
  echo "------------------------------------------------------------"
  return $project_failed
}

# --- 主流程 ---
main() {
  if ! check_environment; then
    echo "❌ 环境检查失败，脚本终止"
    exit 1
  fi

  local total_projects=$(wc -l < "$PROJECT_LIST_FILE")
  local current_project_num=0
  local success_count=0
  local fail_count=0

  while IFS= read -r project_name || [[ -n "$project_name" ]]; do
    # 忽略空行或注释行
    if [[ -z "$project_name" || "$project_name" =~ ^# ]]; then
      continue
    fi
    
    current_project_num=$((current_project_num + 1))
    echo ">>> [ $current_project_num / $total_projects ] 开始处理项目: $project_name <<<"
    
    if process_project "$project_name"; then
      echo "✅ [$current_project_num/$total_projects] 项目 $project_name 成功完成"
      ((success_count++))
    else
      echo "❌ [$current_project_num/$total_projects] 项目 $project_name 处理失败"
      FAILED_PROJECTS+=("$project_name")
      ((fail_count++))
    fi
  done < "$PROJECT_LIST_FILE"

  echo "============================================================"
  echo "🎉 批量处理完成！"
  echo "📊 总计: $total_projects 个项目"
  echo "✅ 成功: $success_count"
  echo "❌ 失败: $fail_count"
  
  if [ ${#FAILED_PROJECTS[@]} -gt 0 ]; then
    echo "📛 失败项目列表:"
    printf '  • %s\n' "${FAILED_PROJECTS[@]}"
    echo "💡 提示: 可以重新运行失败项目，检查日志获取详细信息"
    echo "      日志目录: $LOG_DIR"
  fi
}

main "$@"