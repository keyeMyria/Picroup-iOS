//
//  LoginState+system.swift
//  Picroup-iOS
//
//  Created by luojie on 2018/5/4.
//  Copyright © 2018年 luojie. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa
import RxFeedback
import Apollo

extension DriverFeedback where State == LoginState {
    
    static func system(client: ApolloClient, appStore: AppStore) -> ([Raw]) -> Disposable {
        
        return { feedbacks in
            let syncAppState = self.syncAppState(appStore: appStore)
            let queryLogin = self.queryLogin(client: client)
            return Driver<Any>.system(
                initialState: State.empty(),
                reduce: logger(identifier: "\(State.self)")(State.reduce),
                feedback: [syncAppState, queryLogin] + feedbacks
                ).drive()
        }
    }
}
