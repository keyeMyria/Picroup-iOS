//
//  FollowersViewController.swift
//  Picroup-iOS
//
//  Created by luojie on 2018/5/22.
//  Copyright © 2018年 luojie. All rights reserved.
//

import UIKit
import Apollo
import RxSwift
import RxCocoa
import RxDataSources
import RxFeedback

class FollowersViewController: ShowNavigationBarViewController {
    
    typealias Dependency = String
    var dependency: Dependency!
    
    @IBOutlet var presenter: FollowersPresenter!
    fileprivate typealias Feedback = (Driver<UserFollowersStateObject>) -> Signal<UserFollowersStateObject.Event>
    
    override func viewDidLoad() {
        super.viewDidLoad()
        presenter.setup(navigationItem: navigationItem)
        setupRxFeedback()
    }
    
    private func setupRxFeedback() {
        
        guard
            let userId = dependency,
            let store = try? UserFollowersStateStore(userId: userId) else {
                return
        }
        
        typealias Section = FollowersPresenter.Section
        
        let uiFeedback: Feedback = bind(self) { (me, state)  in
            let _events = PublishRelay<UserFollowersStateObject.Event>()
            let presenter = me.presenter!
            let subscriptions = [
                state.map { $0.user?.followersCount.value?.description ?? "0" }.map { "\($0) 人" }.drive(me.navigationItem.detailLabel.rx.text),
                store.userFollowersItems().map { [Section(model: "", items: $0)] }.drive(presenter.items(_events)),
                state.map { $0.footerState }.drive(onNext: presenter.loadFooterView.on),
                state.map { $0.isFollowersEmpty }.drive(presenter.isFollowersEmpty),
                ]
            let events: [Signal<UserFollowersStateObject.Event>] = [
                .just(.onTriggerReloadUserFollowers),
                _events.asSignal(),
                state.flatMapLatest {
                    $0.shouldQueryMoreUserFollowers
                        ? presenter.tableView.rx.triggerGetMore
                        : .empty()
                    }.map { .onTriggerGetMoreUserFollowers },
                presenter.tableView.rx.modelSelected(UserObject.self).asSignal().map { .onTriggerShowUser($0._id) },
                ]
            return Bindings(subscriptions: subscriptions, events: events)
        }
        
        let queryUserFollowers: Feedback = react(query: { $0.userFollowersQuery }, effects: composeEffects(shouldQuery: { [weak self] in self?.shouldReactQuery ?? false  }) { query in
            ApolloClient.shared.rx.fetch(query: query, cachePolicy: .fetchIgnoringCacheData).map { $0?.data?.user?.followers }.unwrap()
                .map(UserFollowersStateObject.Event.onGetUserFollowers(isReload: query.cursor == nil))
                .asSignal(onErrorReturnJust: UserFollowersStateObject.Event.onGetUserFollowersError)
        })
        
        let followUser: Feedback = react(query: { $0.followUserQuery }, effects: composeEffects(shouldQuery: { [weak self] in self?.shouldReactQuery ?? false  }) { query in
            ApolloClient.shared.rx.perform(mutation: query).asObservable()
                .map { $0?.data?.followUser }.unwrap()
                .map(UserFollowersStateObject.Event.onFollowUserSuccess)
                .asSignal(onErrorReturnJust: UserFollowersStateObject.Event.onFollowUserError)
        })
        
        let unfollowUser: Feedback = react(query: { $0.unfollowUserQuery }, effects: composeEffects(shouldQuery: { [weak self] in self?.shouldReactQuery ?? false  }) { query in
            ApolloClient.shared.rx.perform(mutation: query).asObservable()
                .map { $0?.data?.unfollowUser }.unwrap()
                .map(UserFollowersStateObject.Event.onUnfollowUserSuccess)
                .asSignal(onErrorReturnJust: UserFollowersStateObject.Event.onUnfollowUserError)
        })
        
        let states = store.states
        
        Signal.merge(
            uiFeedback(states),
            queryUserFollowers(states),
            followUser(states),
            unfollowUser(states)
            )
            .debug("UserFollowersState.Event", trimOutput: true)
            .emit(onNext: store.on)
            .disposed(by: disposeBag)
    }
}

extension UserFollowersStateObject {
    
    var footerState: LoadFooterViewState {
        return LoadFooterViewState.create(
            cursor: userFollowers?.cursor.value,
            items: userFollowers?.items,
            trigger: triggerUserFollowersQuery,
            error: userFollowersError
        )
    }
}
