//
//  ImageDetailViewController.swift
//  Picroup-iOS
//
//  Created by luojie on 2018/4/16.
//  Copyright © 2018年 luojie. All rights reserved.
//

import UIKit
import Material
import RxSwift
import RxCocoa
import RxFeedback
import Apollo

class ImageDetailViewController: HideNavigationBarViewController {
    
    typealias Dependency = RankedMediaQuery.Data.RankedMedium.Item
    var dependency: Dependency!
    
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var backgroundButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupRxFeedback()
    }
    
    private func setupRxFeedback() {
        
        guard let dependency = dependency else { return }
        typealias Feedback = Observable<Any>.Feedback<ImageDetailState, ImageDetailState.Event>
        
        let uiFeedback: Feedback = bind(self) { (me, state) in
            let staredMediumTrigger = PublishRelay<Void>()
            let popTrigger = PublishRelay<Void>()
            weak var weakMe = me
            let showImageComments = { (state: ImageDetailState) in {
                let vc = RouterService.Image.imageCommentsViewController(dependency: state.item)
                weakMe?.navigationController?.pushViewController(vc, animated: true)
                }}
            let subscriptions = [
                state.map { [$0] }.throttle(1, scheduler: MainScheduler.instance).bind(to: me.collectionView .rx.items(cellIdentifier: "ImageDetailCell", cellType: ImageDetailCell.self)) { index, state, cell in
                    let viewModel = ImageDetailCell.ViewModel(imageDetailState: state)
                    cell.configure(
                        with: viewModel,
                        onStarButtonTap: staredMediumTrigger.accept,
                        onCommentsTap: showImageComments(state),
                        onImageViewTap: popTrigger.accept)
                },
                me.backgroundButton.rx.tap.bind(to: popTrigger),
                popTrigger.bind(to: me.rx.pop(animated: true)),
            ]
            let events = [
                state.flatMapLatest { state -> Observable<ImageDetailState.Event>  in
                    guard state.staredMedium.data == nil && !state.staredMedium.trigger else {
                        return .empty()
                    }
                    return staredMediumTrigger.map { .staredMedium(.trigger) }
                }
            ]
            return Bindings(subscriptions: subscriptions, events: events)
        }
        
        let queryMedium: Feedback = react(query: { $0.meduim.query }) { query in
            ApolloClient.shared.rx.fetch(query: query, cachePolicy: .fetchIgnoringCacheData).asObservable().map { $0?.data?.medium }.unwrap()
                .map { .meduim(.onSuccess($0)) }
                .catchError  { error in .just(.meduim(.onError(error))) }
        }

        let starMedium: Feedback = react(query: { $0.staredMedium.query }) { query in
            ApolloClient.shared.rx.perform(mutation: query).asObservable().map { $0?.data?.starMedium }.unwrap()
                .map { .staredMedium(.onSuccess($0)) }
                .catchError  { error in .just(.staredMedium(.onError(error))) }
        }
        
        Observable<Any>.system(
            initialState: ImageDetailState.empty(userId: Config.userId, item: dependency),
            reduce: logger(identifier: "ImageDetailState")(ImageDetailState.reduce),
            scheduler: MainScheduler.instance,
            scheduledFeedback:
            uiFeedback,
            queryMedium,
            starMedium
        )
            .subscribe()
            .disposed(by: disposeBag)
        
        collectionView.rx.setDelegate(self).disposed(by: disposeBag)
    }
}

extension ImageDetailViewController: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        let imageHeight = width / CGFloat(dependency.detail?.aspectRatio ?? 1)
        let height = imageHeight + 8 + 56 + 48 + 48
        return CGSize(width: width, height: height)
    }
}