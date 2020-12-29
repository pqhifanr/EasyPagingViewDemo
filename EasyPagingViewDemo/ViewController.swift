//
//  ViewController.swift
//  EasyPagingViewDemo
//
//  Created by pengquanhua on 2020/12/27.
//  Copyright © 2020 pengquanhua. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    var view0: UIScrollView!
    let view1 = UIView()
    var view2: EasyListContentView!
    let containerView = EasyPagingView()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let viewWidth = UIScreen.main.bounds.width
        let viewHeight = UIScreen.main.bounds.height
        
        containerView.frame = self.view.bounds
        containerView.dataSource = self
        containerView.contentInsetAdjustmentBehavior = .never
        self.view.addSubview(containerView)
        
        view0 = UIScrollView(frame: CGRect(origin: .zero, size: CGSize(width: viewWidth, height: 400)))
        view0.contentSize = CGSize(width: viewWidth, height: viewHeight*1.2)
        view0.backgroundColor = .purple
        containerView.contentView.addSubview(view0)
        
        view1.frame = CGRect(origin: .zero, size: CGSize(width: viewWidth, height: 64))
        view1.backgroundColor = .blue
        containerView.pagePinView = view1
        
        containerView.reloadData()
//        view2 = EasyListContentView(frame: CGRect(origin: .zero, size: CGSize(width: viewWidth, height: viewHeight)))
//        view2.backgroundColor = .brown
//        containerView.contentView.addSubview(view2)
//
//        containerView.contentView.bringSubviewToFront(view1)
        
    }
}

extension ViewController: EasyPagingViewDataSource {
    func numberOfLists(in easyPagingView: EasyPagingView) -> Int {
        return 3
    }
    
    func easyPagingView(_ easyContainerScrollView: EasyPagingView, pageForItemAt index: Int) -> EasyPagingViewPageViewDelegate {
        let cell = EasyListContentView(frame: self.view.bounds)
        if index%2 == 0 {
            cell.pageScrollView.backgroundColor = .cyan
        }
        return cell
    }
}

