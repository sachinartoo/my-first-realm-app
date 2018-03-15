////////////////////////////////////////////////////////////////////////////
//
// Copyright 2018 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

import UIKit
import RealmSwift

// Configure the permissions on the Realm and each model class.
// This will only succeed the first time that this code is executed. Subsequent attempts
// will silently fail due to `canSetPermissions` having already been removed.
//
// NOTE: This initial configuration of permissions would typically be done by an admin via
// Realm Studio or a dedicated script, not as part of your app's logic. We show it here
// solely to demonstrate a more advanced use of the Swift API.
func initializeRealmPermissions(_ realm: Realm) {
    // Ensure that class-level permissions cannot be modified by anyone but admin users.
    // The Project type can be queried, while Item cannot. This means that the only Item
    // objects that will be synchronized are those associated with our Projects.
    let queryable = [Project.className(): true, Item.className(): false]
    for cls in [Project.self, Item.self] {
        let classPermissions = realm.objects(ClassPermission.self).filter("name = %@", cls.className()).first!
        let everyonePermission = classPermissions.permissions.findOrCreate(forRoleNamed: "everyone")
        everyonePermission.canQuery = queryable[cls.className()]!
        everyonePermission.canSetPermissions = false
    }

    // Ensure that the schema and Realm-level permissions cannot be modified by anyone but admin users.
    let realmPermissions = realm.objects(RealmPermission.self).first!
    let everyonePermission = realmPermissions.permissions.findOrCreate(forRoleNamed: "everyone")
    everyonePermission.canModifySchema = false
    // `canSetPermissions` must be disabled last, as it would otherwise prevent other permission changes
    // from taking effect.
    everyonePermission.canSetPermissions = false
}

// Ensure there's a role named for the user with the user as a member.
func ensureRoleExists(_ user: SyncUser, _ realm: Realm) {
    let identity = user.identity!
    guard realm.objects(PermissionRole.self).filter("name = %@ AND ANY users.identity = %@",
                                                    identity, identity).isEmpty
    else {
        return
    }

    let permissionUser = realm.create(PermissionUser.self, value: [identity], update: true)
    let role = realm.create(PermissionRole.self, value: [identity], update: true)
    role.users.append(permissionUser)
}

// Initialize the default permissions of the Realm.
// This is done asynchronously, as we must first wait for the Realm to download from the server
// to ensure that we don't end up with the same user being added to a role multiple times.
func initializePermissions(_ user: SyncUser, completion: @escaping (Error?) -> Void) {
    Realm.asyncOpen(configuration: SyncConfiguration.automatic(user: user)) { (realm, error) in
        guard let realm = realm else {
            completion(error)
            return
        }

        try! realm.write {
            initializeRealmPermissions(realm)
            ensureRoleExists(user, realm)
        }

        completion(nil)
    }
}

class WelcomeViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        title = "Welcome"
        
        if let _ = SyncUser.current {
            // We have already logged in here!
            self.navigationController?.viewControllers = [ProjectsViewController()]
        } else {
            let alertController = UIAlertController(title: "Login to Realm Cloud", message: "Supply a nice nickname!", preferredStyle: .alert)
            
            alertController.addAction(UIAlertAction(title: "Login", style: .default) { [weak self] _ in
                let textField = alertController.textFields![0]
                let creds = SyncCredentials.nickname(textField.text!)
                
                SyncUser.logIn(with: creds, server: Constants.AUTH_URL) { [weak self](user, error) in
                    guard let user = user else {
                        fatalError(error!.localizedDescription)
                    }

                    initializePermissions(user) { error in
                        if let error = error {
                            fatalError(error.localizedDescription)
                        }

                        self?.navigationController?.viewControllers = [ProjectsViewController()]
                    }
                }
            })
            alertController.addTextField() { textField in
                textField.placeholder = "A Name for your user"
            }
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    
}
