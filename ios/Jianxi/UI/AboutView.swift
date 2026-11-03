import SwiftUI
import UIKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var licenseOpen = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(red: 0.13, green: 0.42, blue: 0.33))
                        Text("简洗")
                            .font(.title.weight(.semibold))
                        Text("版本 \(version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("使用 SwiftUI 构建的独立洗衣客户端。")
                        .font(.body)
                    if let url = URL(string: "https://github.com/xiyuchengxu/jianxi") {
                        Link(destination: url) {
                            Label("GitHub · 项目源码", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(Color(uiColor: .secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("开源协议")
                            .font(.headline)
                        Text("MIT License")
                        Button("阅读完整协议") { licenseOpen = true }
                    }
                    Text("简洗是独立开源项目，与原服务平台无隶属关系。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("关于简洗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $licenseOpen) {
                NavigationStack {
                    ScrollView {
                        Text(Self.license)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: 560, alignment: .leading)
                            .padding(20)
                            .frame(maxWidth: .infinity)
                    }
                    .navigationTitle("MIT License")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") { licenseOpen = false }
                        }
                    }
                }
            }
        }
    }

    private static let license = """
    MIT License

    Copyright (c) 2026 YuCheng (xiyuchengxu)

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
}
