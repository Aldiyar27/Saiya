import SwiftUI

struct ChatView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var input = ""
    @State private var confirmClear = false
    private let chips = ["Как мой сон?", "Мне грустно", "Что с водой?", "Идея на вечер", "Как улучшить сон?",
                         "Поддержи меня", "Расскажи что-нибудь забавное"]

    var body: some View {
        Nav {
            VStack(spacing: 0) {
                if !vm.aiReady { banner }
                messages
                chipsRow
                inputBar
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Saiya AI")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { confirmClear = true } label: { Image(systemName: "trash") }
                        .disabled(vm.chat.isEmpty)
                }
            }
            .alert("Очистить чат?", isPresented: $confirmClear) {
                Button("Очистить", role: .destructive) { vm.clearChat() }
                Button("Отмена", role: .cancel) {}
            } message: { Text("История переписки будет удалена с этого устройства.") }
        }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Theme.mint)
            Text(vm.aiEnabled ? "Нужен ключ Gemini: ⚙︎ на экране «Сегодня»"
                              : "AI выключен. При включении усреднённая сводка уходит в Gemini.")
                .font(.caption)
            Spacer()
            if !vm.aiEnabled { Button("Включить") { vm.aiEnabled = true }.font(.caption.bold()) }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(Theme.card)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if vm.chat.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Theme.mint)
                            Text("Привет, я Saiya").font(.title2.bold())
                            Text("Можно просто поболтать — про день, сон или настроение.")
                                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        }.padding(.top, 70)
                    }
                    ForEach(vm.chat) { m in bubble(m).id(m.id) }
                    if vm.isSending {
                        Text("печатает…").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
                    }
                }.padding()
            }
            .onChange(of: vm.chat.count) { _ in
                if let last = vm.chat.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { c in
                    Button { Task { await vm.send(c) } } label: {
                        Text(c).font(.footnote)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(Theme.mint.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isSending)
                }
            }.padding(.horizontal).padding(.vertical, 6)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Напиши сообщение…", text: $input).textFieldStyle(.roundedBorder)
            Button {
                let text = input; input = ""
                Task { await vm.send(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title).foregroundStyle(Theme.mint)
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isSending)
        }.padding([.horizontal, .bottom])
    }

    private func bubble(_ m: ChatMessage) -> some View {
        Text(m.text)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(m.role == .user ? Theme.mint.opacity(0.2) : Theme.card,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 300, alignment: m.role == .user ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: m.role == .user ? .trailing : .leading)
    }
}
