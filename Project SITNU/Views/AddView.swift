//
//  AddView.swift
//  Project SITNU
//
//  Created by Nils Bergmann on 19/09/2020.
//

import SwiftUI

class UntisAccountStore: ObservableObject {
    @Published var username: String = "";
    @Published var password: String = "";
    @Published var useSecretLogin: Bool = false;
    
    var authType: AuthType {
        if useSecretLogin {
            return .SECRET
        }
        return .PASSWORD;
    };
    @Published var setDisplayName: String = "";
    @Published var primary: Bool = false;
    @Published var preferShortRoom: Bool = false;
    @Published var preferShortSubject: Bool = false;
    @Published var preferShortTeacher: Bool = false;
    @Published var preferShortClass: Bool = false;
    @Published var showRoomInsteadOfTime: Bool = false;
}

struct AddView: View {
    @State var school: School;
    @State var acc: UntisAccountStore = UntisAccountStore()
    @State var testing: Bool = false;
    @State var error: String?;
    @State var untis: UntisClient?;
    @State var basicCredentials: BasicUntisCredentials?;
    @Environment(WatchConnectivityStore.self) var store
    @EnvironmentObject var addNavigationController: AddNavigationController;
    @Environment(\.dismiss) var dismiss;

    private let editingAccountId: UUID?;

    init(school: School) {
        self.school = school;
        self.editingAccountId = nil;
        self.acc.useSecretLogin = school.useSecret;
        if !school.user.isEmpty {
            self.acc.username = school.user;
        }
        if !school.password.isEmpty {
            self.acc.password = school.password;
        }
    }

    init(existingAccount: UntisAccount) {
        self.editingAccountId = existingAccount.id;
        _school = State(initialValue: School(server: existingAccount.server, displayName: existingAccount.displayName, loginName: existingAccount.school, schoolId: 0, address: ""));
        let store = UntisAccountStore();
        store.username = existingAccount.username;
        store.password = existingAccount.password;
        store.useSecretLogin = existingAccount.authType == .SECRET;
        store.setDisplayName = existingAccount.setDisplayName ?? "";
        store.primary = existingAccount.primary;
        store.preferShortRoom = existingAccount.preferShortRoom;
        store.preferShortSubject = existingAccount.preferShortSubject;
        store.preferShortTeacher = existingAccount.preferShortTeacher;
        store.preferShortClass = existingAccount.preferShortClass;
        store.showRoomInsteadOfTime = existingAccount.showRoomInsteadOfTime;
        _acc = State(initialValue: store);
    }
    
    var body: some View {
        Form {
            Section(header: Text("Server & School")) {
                TextField("Server", text: self.$school.server)
                TextField("School", text: self.$school.loginName)
            }
            Section(header: Text("Settings")) {
                TextField("Displayname (Optional)", text: self.$acc.setDisplayName)
                if !self.needsToBePrimary() {
                    Toggle(isOn: self.$acc.primary) {
                        Text("Add as Primary")
                    }.disabled(testing)
                }
                Text("Show room instead of time")
                Toggle("Room", isOn: self.$acc.showRoomInsteadOfTime)
                Text("Prefer the short representation of: ")
                Toggle("Rooms", isOn: self.$acc.preferShortRoom)
                Toggle("Teachers", isOn: self.$acc.preferShortTeacher)
                Toggle("Subjects", isOn: self.$acc.preferShortSubject)
                // Toggle("Classes", isOn: self.$acc.preferShortClass) // Currently not in use
            }
            Section(header: Text("Login")) {
                TextField("Username", text: self.$acc.username)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(testing)
                SecureField("Password", text: self.$acc.password)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(testing)
                Toggle("Use secret", isOn: self.$acc.useSecretLogin)
                if self.error != nil {
                    Text(self.error!)
                        .foregroundColor(.red)
                }
                Button(editingAccountId != nil ? "Test login and save" : "Test login and add", action: { self.testLoginAndAdd() })
                    .disabled(testing)
            }
        }
        .navigationBarTitle(self.school.displayName)
    }
    
    func needsToBePrimary() -> Bool {
        let otherAccounts = store.accounts.filter { $0.id != editingAccountId }
        if otherAccounts.isEmpty {
            return true;
        }
        return !otherAccounts.contains(where: { $0.primary })
    }
    
    func testLoginAndAdd() {
        if self.testing {
            return;
        }
        withAnimation {
            self.error = nil;
            self.testing = true;
        }
        self.untis = nil;
        self.basicCredentials = nil;
        self.basicCredentials = BasicUntisCredentials(username: self.acc.username, password: self.acc.password, server: self.school.server, school: self.school.loginName.replacingOccurrences(of: " ", with: "+").components(separatedBy: "+").map({ $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! }).joined(separator: "+"), authType: self.acc.authType);
        
        print(self.basicCredentials)
        self.untis = UntisClient(credentials: self.basicCredentials!);
        self.untis!.getLatestImportTime(force: true, cachedHandler: nil) { result in
            self.handleUntisResponse(result: result);
        }
    }
    
    func handleUntisResponse(result: Swift.Result<Int64, Error>) {
        switch result {
        case .success:
            let primary = self.needsToBePrimary() || self.acc.primary;
            let setDisplayName: String? = self.acc.setDisplayName.isEmpty ? nil : self.acc.setDisplayName;
            let encodedSchool = self.school.loginName.replacingOccurrences(of: " ", with: "+").components(separatedBy: "+").map({ $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! }).joined(separator: "+");
            if primary {
                for (index, _) in self.store.accounts.enumerated() {
                    self.store.accounts[index].primary = false;
                }
            }
            if let editId = editingAccountId, let existingIndex = self.store.accounts.firstIndex(where: { $0.id == editId }) {
                let updated = UntisAccount(id: editId, username: self.acc.username, password: self.acc.password, server: self.school.server, school: encodedSchool, setDisplayName: setDisplayName, authType: self.acc.authType, primary: primary, preferShortRoom: self.acc.preferShortRoom, preferShortSubject: self.acc.preferShortSubject, preferShortTeacher: self.acc.preferShortTeacher, preferShortClass: self.acc.preferShortClass, showRoomInsteadOfTime: self.acc.showRoomInsteadOfTime);
                self.store.accounts[existingIndex] = updated;
                self.store.saveToKeyChain();
                self.store.sync();
                dismiss();
            } else {
                let acc = UntisAccount(id: UUID(), username: self.acc.username, password: self.acc.password, server: self.school.server, school: encodedSchool, setDisplayName: setDisplayName, authType: self.acc.authType, primary: primary, preferShortRoom: self.acc.preferShortRoom, preferShortSubject: self.acc.preferShortSubject, preferShortTeacher: self.acc.preferShortTeacher, preferShortClass: self.acc.preferShortClass, showRoomInsteadOfTime: self.acc.showRoomInsteadOfTime);
                self.store.accounts.append(acc);
                self.store.saveToKeyChain();
                self.store.sync();
                self.addNavigationController.addsAccount = false;
            }
            break;
        case .failure(let error):
            print("Error: \(error.localizedDescription)")
            withAnimation {
                self.error = error.localizedDescription;
            }
            break;
        }
        withAnimation {
            self.testing = false;
        }
    }
}

struct AddView_Previews: PreviewProvider {
    static let testSchool = School(server: "mese.webuntis.com", displayName: "MESE", loginName: "mese", schoolId: 1, address: "Whatever")
    
    static var previews: some View {
        AddView(school: testSchool)
    }
}
