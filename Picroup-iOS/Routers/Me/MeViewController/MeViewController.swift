//
//  MeViewController.swift
//  Picroup-iOS
//
//  Created by luojie on 2018/4/10.
//  Copyright © 2018年 luojie. All rights reserved.
//

import UIKit
import Apollo
import RxSwift
import RxCocoa
import RxGesture
import RxFeedback
import RxViewController

private func mapMoreButtonTapToEvent() -> Signal<MeStateObject.Event> {
    return DefaultWireframe.shared
        .promptFor(cancelAction: "取消", actions: ["更新个人信息", "应用反馈", "退出登录"])
        .asSignalOnErrorRecoverEmpty()
        .flatMap { action in
            switch action {
            case "更新个人信息":  return .just(.onTriggerUpdateUser)
            case "应用反馈":     return .just(.onTriggerAppFeedback)
            case "退出登录":     return .just(.onLogout)
            default:            return .empty()
            }
    }
}

class MeViewController: HideNavigationBarViewController {
    
    fileprivate typealias Feedback = (Driver<MeStateObject>) -> Signal<MeStateObject.Event>
    @IBOutlet fileprivate var presenter: MePresenter!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupRxFeedback()
    }
    
    private func setupRxFeedback() {
        
        guard let store = try? MeStateStore(),
            let appStateService = appStateService,
            let appStore = appStateService.appStore
            else { return }
        
        typealias Section = MePresenter.Section

        let uiFeedback: Feedback = bind(self) { (me, state) in
            let presenter = me.presenter!
            let myMediaFooterState = BehaviorRelay<LoadFooterViewState>(value: .empty)
            let myStaredMediaFooterState = BehaviorRelay<LoadFooterViewState>(value: .empty)
            let subscriptions: [Disposable] = [
                appStore.me().drive(presenter.me),
                state.map { $0.selectedTabIndex }.distinctUntilChanged().drive(presenter.selectedTabIndex),
                store.myMediaItems().map { [Section(model: "", items: $0)] }.drive(presenter.myMediaItems(myMediaFooterState.asDriver())),
                store.myStaredMediaItems().map { [Section(model: "", items: $0)] }.drive(presenter.myStaredMediaItems(myStaredMediaFooterState.asDriver())),
                state.map { $0.myMediaFooterState }.drive(myMediaFooterState),
                state.map { $0.myStaredMediaFooterState }.drive(myStaredMediaFooterState),
                Signal.just(.onTriggerReloadMe).emit(to: appStateService.events),
                me.rx.viewWillAppear.asSignal().map { _ in .onTriggerReloadMe }.emit(to: appStateService.events),
                ]
            let events: [Signal<MeStateObject.Event>] = [
                .of(.onTriggerReloadMyMedia, .onTriggerReloadMyStaredMedia),
                presenter.moreButton.rx.tap.asSignal().flatMapLatest(mapMoreButtonTapToEvent),
                presenter.myMediaButton.rx.tap.asSignal().map { .onChangeSelectedTab(.myMedia) },
                presenter.myStaredMediaButton.rx.tap.asSignal().map { .onChangeSelectedTab(.myStaredMedia) },
                state.flatMapLatest {
                    $0.shouldQueryMoreMyMedia
                        ? presenter.myMediaCollectionView.rx.triggerGetMore
                        : .empty()
                    }.map { .onTriggerGetMoreMyMedia },
                state.flatMapLatest {
                    $0.shouldQueryMoreMyStaredMedia
                        ? presenter.myStardMediaCollectionView.rx.triggerGetMore
                        : .empty()
                    }.map { .onTriggerGetMoreMyStaredMedia },
                me.rx.viewWillAppear.asSignal().map { _ in .onTriggerReloadMyMediaIfNeeded },
                me.rx.viewWillAppear.asSignal().map { _ in .onTriggerReloadMyStaredMediaIfNeeded },
                presenter.myMediaCollectionView.rx.modelSelected(MediumObject.self).asSignal().map { .onTriggerShowImage($0._id) },
                presenter.myStardMediaCollectionView.rx.modelSelected(MediumObject.self).asSignal().map { .onTriggerShowImage($0._id) },
                presenter.reputationButton.rx.tap.asSignal().map { _ in .onTriggerShowReputations },
                presenter.followersButton.rx.tap.asSignal().map { _ in .onTriggerShowUserFollowers },
                presenter.followingsButton.rx.tap.asSignal().map { _ in .onTriggerShowUserFollowings },
                presenter.meBackgroundView.rx.tapGesture().when(.recognized).asSignalOnErrorRecoverEmpty().map { _ in .onTriggerPop },
                ]
            return Bindings(subscriptions: subscriptions, events: events)
        }
        
//        let queryMe: Feedback = react(query: { $0.meQuery }) { query in
//            ApolloClient.shared.rx.fetch(query: query, cachePolicy: .fetchIgnoringCacheData).map { $0?.data?.user?.fragments.userDetailFragment }.unwrap()
//                .map(MeStateObject.Event.onGetMeSuccess)
//                .asSignal(onErrorReturnJust: MeStateObject.Event.onGetMeError)
//        }
        
        let queryMyMedia: Feedback = react(query: { $0.myMediaQuery }) { query in
            ApolloClient.shared.rx.fetch(query: query, cachePolicy: .fetchIgnoringCacheData)
                .map { $0?.data?.user?.media.fragments.cursorMediaFragment }.unwrap()
                .map(MeStateObject.Event.onGetMyMedia(isReload: query.cursor == nil))
                .asSignal(onErrorReturnJust: MeStateObject.Event.onGetMyMediaError)
        }
        
        let queryMyStaredMedia: Feedback = react(query: { $0.myStaredMediaQuery }) { query in
            ApolloClient.shared.rx.fetch(query: query, cachePolicy: .fetchIgnoringCacheData)
                .map { $0?.data?.user?.staredMedia.fragments.cursorMediaFragment }.unwrap()
                .map(MeStateObject.Event.onGetMyStaredMedia(isReload: query.cursor == nil))
                .asSignal(onErrorReturnJust: MeStateObject.Event.onGetMyStaredMediaError)
        }
        
        let states = store.states
//            .debug("MeState", trimOutput: true)

        Signal.merge(
            uiFeedback(states),
            queryMyMedia(states),
            queryMyStaredMedia(states)
            )
            .debug("MeState.Event", trimOutput: true)
            .emit(onNext: store.on)
            .disposed(by: disposeBag)
        

        Signal.merge(
            presenter.myMediaCollectionView.rx.shouldHideNavigationBar(),
            presenter.myStardMediaCollectionView.rx.shouldHideNavigationBar()
            )
            .emit(onNext: { [weak presenter, weak self] in
                presenter?.hideDetailLayoutConstraint.isActive = $0
                UIView.animate(withDuration: 0.3) { self?.view.layoutIfNeeded() }
            })
            .disposed(by: disposeBag)

    }
}

extension MeStateObject {
    
    var myMediaFooterState: LoadFooterViewState {
        let (cursor, trigger, error) = (myMedia?.cursor.value, triggerMyMediaQuery, myMediaError)
        return LoadFooterViewState.create(cursor: cursor, trigger: trigger, error: error)
    }
    
    var myStaredMediaFooterState: LoadFooterViewState {
        let (cursor, trigger, error) = (myStaredMedia?.cursor.value, triggerMyStaredMediaQuery, myStaredMediaError)
        return LoadFooterViewState.create(cursor: cursor, trigger: trigger, error: error)
    }
}


