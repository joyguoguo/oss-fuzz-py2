#!/bin/bash

# OSS-Fuzz批量测试Python项目脚本
# 基础目录配置
OSS_FUZZ_DIR="/home/jiayiguo/oss-fuzz-py/oss-fuzz"
PROJECTS_DIR="$OSS_FUZZ_DIR/projects"
LOG_FILE="oss_fuzz_batch_test_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG="oss_fuzz_errors_$(date +%Y%m%d_%H%M%S).log"

# 创建日志文件
touch "$LOG_FILE"
touch "$ERROR_LOG"

echo "==== 开始OSS-Fuzz批量测试 ====" | tee -a "$LOG_FILE"
echo "开始时间: $(date)" | tee -a "$LOG_FILE"

# 获取所有项目名称
readarray -t PROJECTS < <(ls "$PROJECTS_DIR")

for PROJECT_NAME in "${PROJECTS[@]}"; do
    echo -e "\n=== 处理项目: $PROJECT_NAME ===" | tee -a "$LOG_FILE"
    
    # 检查是否为Python项目[1,2](@ref)
    if ! grep -q "language: python" "$PROJECTS_DIR/$PROJECT_NAME/project.yaml"; then
        echo "  跳过非Python项目" | tee -a "$LOG_FILE"
        continue
    fi

    echo "  确认是Python项目，开始处理..." | tee -a "$LOG_FILE"
    
    # 步骤1: 构建Docker镜像
    echo "  步骤1: 构建Docker镜像..." | tee -a "$LOG_FILE"
    if ! python3 "$OSS_FUZZ_DIR/infra/helper.py" build_image "$PROJECT_NAME" >> "$LOG_FILE" 2>&1; then
        echo "    [错误] 镜像构建失败！跳过项目" | tee -a "$ERROR_LOG"
        continue
    fi

    # 步骤2: 使用address sanitizer构建fuzzers
    echo "  步骤2: 构建address sanitizer fuzzers..." | tee -a "$LOG_FILE"
    if ! python3 "$OSS_FUZZ_DIR/infra/helper.py" build_fuzzers --sanitizer address "$PROJECT_NAME" >> "$LOG_FILE" 2>&1; then
        echo "    [错误] fuzzers构建失败！跳过项目" | tee -a "$ERROR_LOG"
        continue
    fi

    # 步骤3: 检查构建结果
    echo "  步骤3: 检查构建结果..." | tee -a "$LOG_FILE"
    if ! python3 "$OSS_FUZZ_DIR/infra/helper.py" check_build "$PROJECT_NAME" >> "$LOG_FILE" 2>&1; then
        echo "    [错误] 构建检查失败！跳过项目" | tee -a "$ERROR_LOG"
        continue
    fi

    # 步骤4: 查找并运行所有fuzz_target
    echo "  步骤4: 查找fuzz_targets..." | tee -a "$LOG_FILE"
    readarray -t FUZZ_TARGETS < <(find "$PROJECTS_DIR/$PROJECT_NAME" -name 'fuzz_*.py' -exec basename {} .py \;)
    
    if [ ${#FUZZ_TARGETS[@]} -eq 0 ]; then
        echo "    未找到fuzz_targets！跳过项目" | tee -a "$ERROR_LOG"
        continue
    fi

    for TARGET in "${FUZZ_TARGETS[@]}"; do
        echo "    运行fuzz_target: $TARGET (3分钟超时)..." | tee -a "$LOG_FILE"
        timeout 180s python3 "$OSS_FUZZ_DIR/infra/helper.py" run_fuzzer "$PROJECT_NAME" "$TARGET" >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 124 ]; then
            echo "    [超时] $TARGET 已自动终止" | tee -a "$LOG_FILE"
        fi
    done

    # 步骤5: 构建覆盖率检测版本
    echo "  步骤5: 构建coverage fuzzers..." | tee -a "$LOG_FILE"
    if ! python3 "$OSS_FUZZ_DIR/infra/helper.py" build_fuzzers --sanitizer coverage "$PROJECT_NAME" >> "$LOG_FILE" 2>&1; then
        echo "    [错误] coverage构建失败！跳过项目" | tee -a "$ERROR_LOG"
        continue
    fi

    # 步骤6: 生成覆盖率报告
    echo "  步骤6: 生成覆盖率报告..." | tee -a "$LOG_FILE"
    python3 "$OSS_FUZZ_DIR/infra/helper.py" coverage --no-serve "$PROJECT_NAME" >> "$LOG_FILE" 2>&1
done

echo -e "\n==== 批量测试完成 ====" | tee -a "$LOG_FILE"
echo "结束时间: $(date)" | tee -a "$LOG_FILE"
echo "详细日志: $LOG_FILE" | tee -a "$LOG_FILE"
echo "错误日志: $ERROR_LOG" | tee -a "$LOG_FILE"