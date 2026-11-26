# Builds and copies the Rust artifacts required by the selected Windows runner configuration.
file(MAKE_DIRECTORY "${OPERIT_OUTPUT_DIRECTORY}")

if(NOT OPERIT_RUSTUP_TOOLCHAIN)
  if(DEFINED ENV{RUSTUP_TOOLCHAIN} AND NOT "$ENV{RUSTUP_TOOLCHAIN}" STREQUAL "")
    set(OPERIT_RUSTUP_TOOLCHAIN "$ENV{RUSTUP_TOOLCHAIN}")
  else()
    set(OPERIT_RUSTUP_TOOLCHAIN "stable-x86_64-pc-windows-msvc")
  endif()
endif()

set(OPERIT_CARGO_ENV
  "RUSTFLAGS=-Awarnings"
  "CARGO_TERM_COLOR=never"
)
if(OPERIT_CARGO_HOME)
  list(APPEND OPERIT_CARGO_ENV "CARGO_HOME=${OPERIT_CARGO_HOME}")
endif()
if(OPERIT_RUSTUP_HOME)
  list(APPEND OPERIT_CARGO_ENV "RUSTUP_HOME=${OPERIT_RUSTUP_HOME}")
endif()
if(OPERIT_RUSTUP_TOOLCHAIN)
  list(APPEND OPERIT_CARGO_ENV "RUSTUP_TOOLCHAIN=${OPERIT_RUSTUP_TOOLCHAIN}")
endif()
if(DEFINED ENV{JAVA_HOME} AND NOT "$ENV{JAVA_HOME}" STREQUAL "")
  list(APPEND OPERIT_CARGO_ENV "JAVA_HOME=$ENV{JAVA_HOME}")
endif()

if(OPERIT_BUILD_CONFIG STREQUAL "Debug")
  list(APPEND OPERIT_CARGO_ENV "CARGO_PROFILE_DEV_DEBUG=2")
  set(OPERIT_CARGO_ARGS build --manifest-path "${OPERIT_FLUTTER_BRIDGE_CRATE}/Cargo.toml")
  set(OPERIT_CARGO_DLL "${OPERIT_FLUTTER_BRIDGE_CRATE}/target/debug/operit_flutter_bridge.dll")
  set(OPERIT_CARGO_LABEL Debug)
else()
  set(OPERIT_CARGO_ARGS build --manifest-path "${OPERIT_FLUTTER_BRIDGE_CRATE}/Cargo.toml" --release)
  set(OPERIT_CARGO_DLL "${OPERIT_FLUTTER_BRIDGE_CRATE}/target/release/operit_flutter_bridge.dll")
  set(OPERIT_CARGO_LABEL release)
endif()

# Deploy the matching debug symbols beside the loaded DLL for Rust stack resolution.
if(OPERIT_BUILD_CONFIG STREQUAL "Debug")
  set(OPERIT_CARGO_PDB "${OPERIT_FLUTTER_BRIDGE_CRATE}/target/debug/operit_flutter_bridge.pdb")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env ${OPERIT_CARGO_ENV}
    "${OPERIT_PLUGIN_SYNC_PYTHON}" "${OPERIT_REPO_ROOT}/tools/build_scripts/cargo_build.py"
    "${OPERIT_CARGO_EXECUTABLE}" ${OPERIT_CARGO_ARGS}
  WORKING_DIRECTORY "${OPERIT_FLUTTER_BRIDGE_CRATE}"
  RESULT_VARIABLE OPERIT_CARGO_RESULT
)
if(NOT OPERIT_CARGO_RESULT EQUAL 0)
  message(FATAL_ERROR "operit flutter bridge ${OPERIT_CARGO_LABEL} build failed: ${OPERIT_CARGO_RESULT}")
endif()
get_filename_component(OPERIT_CARGO_OUTPUT_DIRECTORY "${OPERIT_CARGO_DLL}" DIRECTORY)

# Fork 补丁：CMake 的 RUNTIME_OUTPUT_DIRECTORY 在 Visual Studio 生成器下会被追加配置名，
# 导致 operit_local_llm.dll 落在 target/release/Release/ 而不是 target/release/，原来的
# 固定路径 copy 就直接失败（MSB8066）。这里改成先按候选路径找，再递归兜底。
set(OPERIT_LOCAL_LLM_DLL "")
foreach(OPERIT_CANDIDATE
    "${OPERIT_CARGO_OUTPUT_DIRECTORY}/operit_local_llm.dll"
    "${OPERIT_CARGO_OUTPUT_DIRECTORY}/Release/operit_local_llm.dll"
    "${OPERIT_CARGO_OUTPUT_DIRECTORY}/RelWithDebInfo/operit_local_llm.dll"
    "${OPERIT_FLUTTER_BRIDGE_CRATE}/target/local-llm/operit_local_llm.dll")
  if(EXISTS "${OPERIT_CANDIDATE}")
    set(OPERIT_LOCAL_LLM_DLL "${OPERIT_CANDIDATE}")
    break()
  endif()
endforeach()
if(NOT OPERIT_LOCAL_LLM_DLL)
  file(GLOB_RECURSE OPERIT_LOCAL_LLM_SEARCH
    "${OPERIT_FLUTTER_BRIDGE_CRATE}/target/release/operit_local_llm.dll"
    "${OPERIT_REPO_ROOT}/target/local-llm/operit_local_llm.dll"
    "${OPERIT_REPO_ROOT}/target/local-llm/*/operit_local_llm.dll"
    "${OPERIT_REPO_ROOT}/target/local-llm/*/*/operit_local_llm.dll"
    "${OPERIT_REPO_ROOT}/target/local-llm/*/*/*/operit_local_llm.dll")
  list(LENGTH OPERIT_LOCAL_LLM_SEARCH OPERIT_LOCAL_LLM_COUNT)
  if(OPERIT_LOCAL_LLM_COUNT GREATER 0)
    list(GET OPERIT_LOCAL_LLM_SEARCH 0 OPERIT_LOCAL_LLM_DLL)
  endif()
endif()
if(NOT OPERIT_LOCAL_LLM_DLL)
  message(WARNING "operit_local_llm.dll not found; local LLM will be unavailable in this build")
  file(GLOB_RECURSE OPERIT_RELEASE_DLLS "${OPERIT_CARGO_OUTPUT_DIRECTORY}/*.dll")
  message(STATUS "DLLs present under ${OPERIT_CARGO_OUTPUT_DIRECTORY}: ${OPERIT_RELEASE_DLLS}")
endif()

set(OPERIT_RUNTIME_DLLS "${OPERIT_CARGO_DLL}")
if(OPERIT_LOCAL_LLM_DLL)
  list(APPEND OPERIT_RUNTIME_DLLS "${OPERIT_LOCAL_LLM_DLL}")
endif()
foreach(OPERIT_RUNTIME_DLL IN LISTS OPERIT_RUNTIME_DLLS)
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${OPERIT_RUNTIME_DLL}" "${OPERIT_OUTPUT_DIRECTORY}/"
    RESULT_VARIABLE OPERIT_COPY_RESULT
  )
  if(NOT OPERIT_COPY_RESULT EQUAL 0)
    message(FATAL_ERROR
      "Failed to deploy ${OPERIT_RUNTIME_DLL} into ${OPERIT_OUTPUT_DIRECTORY}: ${OPERIT_COPY_RESULT}")
  endif()
endforeach()
if(OPERIT_BUILD_CONFIG STREQUAL "Debug")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${OPERIT_CARGO_PDB}"
      "${OPERIT_OUTPUT_DIRECTORY}/operit_flutter_bridge.pdb"
    RESULT_VARIABLE OPERIT_SYMBOL_COPY_RESULT
  )
  if(NOT OPERIT_SYMBOL_COPY_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to deploy Rust debug symbols: ${OPERIT_CARGO_PDB}")
  endif()
endif()
