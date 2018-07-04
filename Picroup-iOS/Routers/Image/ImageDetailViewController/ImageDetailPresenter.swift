//
//  ImageDetailPresenter.swift
//  Picroup-iOS
//
//  Created by luojie on 2018/5/9.
//  Copyright © 2018年 luojie. All rights reserved.
//

import UIKit
import Material
import RxSwift
import RxCocoa
import RxDataSources

class ImageDetailPresenter: NSObject {
    
    @IBOutlet weak var deleteAlertView: UIView!
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var backgroundButton: UIButton!
    
    typealias Section = AnimatableSectionModel<String, CellStyle>
    typealias DataSource = RxCollectionViewSectionedReloadDataSource<Section>
    
    var dataSource: DataSource?
    
    func items(
        onStarButtonTap: (() -> Void)?,
        onCommentsTap: (() -> Void)?,
        onImageViewTap: (() -> Void)?,
        onUserTap: (() -> Void)?,
        onMoreTap: (() -> Void)?
        ) -> (Observable<[Section]>) -> Disposable {
            dataSource = DataSource(
                configureCell: { dataSource, collectionView, indexPath, cellStyle in
                    switch cellStyle {
                    case .imageDetail(let item):
                        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImageDetailCell", for: indexPath) as! ImageDetailCell
                        cell.configure(
                            with: item,
                            onStarButtonTap: onStarButtonTap,
                            onCommentsTap: onCommentsTap,
                            onImageViewTap: onImageViewTap,
                            onUserTap: onUserTap,
                            onMoreTap: onMoreTap
                        )
                        return cell
                    case .recommendMedium(let item):
                        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "RankMediumCell", for: indexPath) as! RankMediumCell
                        cell.configure(with: item)
                        return cell
                    }
            },
                configureSupplementaryView: { dataSource, collectionView, title, indexPath in
                    return UICollectionReusableView()
            })
        return collectionView.rx.items(dataSource: dataSource!)
    }
}

extension ImageDetailPresenter: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let dataSource = dataSource else { return .zero }
        switch dataSource[indexPath] {
        case .imageDetail(let medium):
            guard !medium.isInvalidated else { return .zero }
//            print("medium", medium)
            let width = collectionView.bounds.width
            let imageHeight = width / CGFloat(medium.detail?.aspectRatio.value ?? 1)
            let height = imageHeight + 8 + 56 + 48 + 1 + 48
            return CGSize(width: width, height: height)
        case .recommendMedium:
            return CollectionViewLayoutManager.size(in: collectionView.bounds)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        guard let dataSource = dataSource else { return .zero }
        switch dataSource[section].model {
        case "recommendMedia":
            return UIEdgeInsets(top: 36, left: 2, bottom: 64, right: 2)
        default:
            return .zero
        }
    }
}

extension ImageDetailPresenter {
    
    enum CellStyle {
        case imageDetail(MediumObject)
        case recommendMedium(MediumObject)
    }
}

extension ImageDetailPresenter.CellStyle {
    
    var recommendMediumId: String? {
        if case .recommendMedium(let medium) = self {
            return medium._id
        }
        return nil
    }
}

extension ImageDetailPresenter.CellStyle: IdentifiableType, Equatable {
    typealias Identity = String
    
    var identity: String {
        switch self {
        case .imageDetail:
            return "imageDetail"
        case .recommendMedium(let medium):
            return medium._id
        }
    }
    
    static func ==(lhs: ImageDetailPresenter.CellStyle, rhs: ImageDetailPresenter.CellStyle) -> Bool {
        switch (lhs, rhs) {
        case (.imageDetail, imageDetail):
            return false
        case (.recommendMedium(let lMedium), .recommendMedium(let rMedium)):
            return lMedium._id == rMedium._id
        default:
            return false
        }
    }
    
}

