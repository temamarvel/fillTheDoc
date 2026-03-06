//
//  FieldMessage.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 06.03.2026.
//


public struct FieldValidationResult: Equatable, Sendable {
    public let state: State
    public let text: String

    public init(_ state: State, _ text: String) {
        self.state = state
        self.text = text
    }

    public enum State: Equatable, Sendable {
        case pass
        case warning
        case error
    }
}
