#!/bin/bash
# 项目仓库setup.py验证脚本
TARGET_DIR="/home/jiayiguo/oss-fuzz-py/oss-fuzz/projects"
VALID_REPORT="valid_projects_$(date +%Y%m%d%H%M).txt"
NO_SETUP_REPORT="no_setup_projects_$(date +%Y%m%d%H%M).txt"
TEMP_DIR="/tmp/oss_repo_check"

mkdir -p "$TEMP_DIR"
: > "$VALID_REPORT"
: > "$NO_SETUP_REPORT"

# 初始化统计
total=0; valid=0; no_setup=0; invalid=0

for project_dir in "$TARGET_DIR"/*; do
  [ ! -d "$project_dir" ] && continue
  ((total++))
  project_name=$(basename "$project_dir")
  
  # 1. 基础文件检查
  missing_files=()
  for file in "Dockerfile" "build.sh" "project.yaml" "fuzz_*.py"; do
    if [ "$file" = "fuzz_*.py" ]; then
      [ -z "$(find "$project_dir" -maxdepth 1 -name 'fuzz_*.py')" ] && missing_files+=("$file")
    elif [ ! -f "$project_dir/$file" ]; then
      missing_files+=("$file")
    fi
  done

  # 2. 检查project.yaml语言配置
  if [ -f "$project_dir/project.yaml" ]; then
    if ! grep -qx "language: python" "$project_dir/project.yaml"; then
      missing_files+=("language配置")
    fi
  else
    missing_files+=("project.yaml")
  fi

  # 3. 解析仓库URL并验证setup.py
  repo_url=""
  if [ -z "${missing_files[*]}" ]; then
    repo_url=$(grep "main_repo:" "$project_dir/project.yaml" | awk '{print $2}')
    if [ -n "$repo_url" ]; then
      repo_name=$(basename "$repo_url" .git)
      # 远程检查仓库根目录（避免完整克隆）
      if git ls-remote --quiet "$repo_url" | grep -q "HEAD"; then
        if git ls-remote --quiet "$repo_url" 'HEAD:setup.py' | grep -q 'setup.py'; then
          valid_projects+=("$project_name")
          echo "$project_name" >> "$VALID_REPORT"
          ((valid++))
        else
          no_setup_projects+=("$project_name")
          echo "$project_name" >> "$NO_SETUP_REPORT"
          ((no_setup++))
        fi
      else
        echo "⚠️ 仓库不可访问: $repo_url" >&2
        ((invalid++))
      fi
    else
      missing_files+=("main_repo配置")
      ((invalid++))
    fi
  else
    ((invalid++))
  fi
done

# 生成报告
valid_pct=$((total > 0 ? valid*100/total : 0))
echo -e "\n\033[1;36m======== 仓库验证报告 ========\033[0m"
echo -e "\033[32m合规项目: $valid ($valid_pct%)\033[0m"
echo -e "\033[33m缺失setup.py: $no_setup\033[0m"
echo -e "\033[31m基础不达标: $invalid\033[0m"
echo -e "\n\033[1;33m合规项目清单: $VALID_REPORT"
echo -e "缺失setup.py项目清单: $NO_SETUP_REPORT\033[0m"