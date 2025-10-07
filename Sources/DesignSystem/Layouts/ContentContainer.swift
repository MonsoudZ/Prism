import SwiftUI
public struct ContentContainer<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View { content.padding().frame(minWidth: 600, minHeight: 400) }
}
