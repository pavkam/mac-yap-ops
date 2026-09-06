// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

enum ACPAsyncTaskFixtures {
    static let spawned = #"{"sessionUpdate":"async_task_spawned","asyncTaskId":"task-7","name":"Watch build","taskType":"shell","description":"Waiting for CI","showInTranscript":true,"canStop":true,"outputFilePath":"/tmp/build.log","toolCallId":"tool-9"}"#
    static let progress = #"{"sessionUpdate":"async_task_progress","asyncTaskId":"task-7","description":"Still running","summary":"3 of 5","lastToolName":"Bash","usage":{"totalTokens":12,"toolUses":3,"durationMs":900},"outputFilePath":"/tmp/build.log","toolCallId":"tool-9"}"#
    static func state(_ state: String) -> String {
        #"{"sessionUpdate":"async_task_state_update","asyncTaskId":"task-7","state":"\#(state)","summary":"Done","outputFilePath":"/tmp/build.log","toolCallId":"tool-9"}"#
    }
}
