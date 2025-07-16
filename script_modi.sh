#!/bin/bash
# OSS-Fuzz Python项目模糊测试脚本
# 使用前：确保已安装 Docker、Git 和 Python3，并配置代理（如需访问 gcr.io）

# 配置区（根据实际项目修改）
PROJECT_NAME="$1"  # 从命令行获取项目名 [1](@ref)
OSS_FUZZ_DIR="/home/jiayiguo/oss-fuzz-py/oss-fuzz"
WORK_DIR="/home/jiayiguo/oss-fuzz-py/oss-fuzz/fuzz_results"
# SANITIZER="address"
TIMEOUT="3600s"

# 初始化环境（无需修改）
init_environment() {
    mkdir -p "$WORK_DIR"
    [[ ! -d "$OSS_FUZZ_DIR" ]] && git clone https://github.com/google/oss-fuzz "$OSS_FUZZ_DIR"
}

# 新增：校验项目目录是否存在
# validate_project() {
#     local project=$1
#     if [[ ! -d "$OSS_FUZZ_DIR/projects/$project" ]]; then
#         echo "[-] 错误：项目 $project 不存在于 $OSS_FUZZ_DIR/projects/"
#         echo "    请先创建目录或检查拼写"
#         exit 1
#     fi
# }

# 构建单个项目
build_project() {
    local project=$1
    echo "=== 构建项目 $project ==="
    
    # 生成项目模板（首次运行）
    # if [ ! -d "$OSS_FUZZ_DIR/projects/$project" ]; then
    #     python3 "$OSS_FUZZ_DIR/infra/helper.py" generate "$project" --language=python
    # fi

    # 重写关键配置文件（适配Python）
    #

    # 执行构建
    echo "build_image "$project""
    
    expect <<EOF
    
    spawn python3 "$OSS_FUZZ_DIR/infra/helper.py" build_image "$project"
    set timeout $TIMEOUT
    
    expect "Pull latest base images (compiler/runtime)? (y/N):"
    send "y\r"
    set timeout $TIMEOUT
    
    expect eof
EOF
    
    echo "build_fuzzers "$project""
    python3 "$OSS_FUZZ_DIR/infra/helper.py" build_fuzzers --sanitizer address --engine libfuzzer "$project"
    python3 infra/helper.py check_build $PROJECT_NAME
    
}

# 运行测试并收集结果
run_fuzzing() {
    local project=$1
    local output_dir="$WORK_DIR/$project"
    mkdir -p "$output_dir"
    
    echo "[+] 测试项目 $project ($TIMEOUT/目标)"
    targets=$(find "$OSS_FUZZ_DIR/build/out/$project" -executable -type f -name 'fuzz*')
    
    for target in $targets; do
        target_name=$(basename "$target")
        echo "  → 测试目标: $target_name"
        mkdir -p $output_dir/corpus_$target_name
        
        # 执行模糊测试
        # timeout "$TIMEOUT" \
        python3 "$OSS_FUZZ_DIR/infra/helper.py" run_fuzzer \
            --corpus-dir="$output_dir/corpus_$target_name" \
            "$project" "$target_name" > "$output_dir/log_$target_name.txt" 2>&1
        
        # 收集覆盖率（需先重建）
        # python3 "$OSS_FUZZ_DIR/infra/helper.py" build_fuzzers --sanitizer=coverage "$project"
        # python3 "$OSS_FUZZ_DIR/infra/helper.py" coverage \
        #     --corpus-dir="$output_dir/corpus_$target_name" \
        #     --fuzz-target="$target_name" \
        #     "$project" > "$output_dir/coverage_$target_name.html" 2>&1
        
        #docker stop $(docker ps -a | grep -v CONTAINER | awk '{print $1}')
        #docker rm $(docker ps -a | grep -v CONTAINER | awk '{print $1}')
        #ocker ps -a | grep -v CONTAINER
    done
}

main() {
    # 校验参数
    if [[ $# -eq 0 ]]; then
        echo "用法: $0 <项目名称>"
        exit 1
    fi
    local project="$1"

    init_environment
    validate_project "$project"  # 新增校验
    
    build_project "$project"
    if python3 "$OSS_FUZZ_DIR/infra/helper.py" check_build "$project"; then
        run_fuzzing "$project"
    else
        echo "[-] $project 构建失败！检查日志: $OSS_FUZZ_DIR/modi_build.log"
        exit 2
    fi
    echo "[√] 项目 $project 测试完成！结果见 $WORK_DIR/$project"
}

# 传递命令行参数
main "$@"
