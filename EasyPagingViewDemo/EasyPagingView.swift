//
//  EasyContainerScrollView.swift
//  ScrollViewDemo
//
//  Created by quanhua on 2020/12/20.
//

import UIKit

// 参考: https://oleb.net/blog/2014/05/scrollviews-inside-scrollviews/

fileprivate let kContentSize = "contentSize"
fileprivate let kContentOffset = "contentOffset"
fileprivate let kFrame = "frame"
fileprivate let kBounds = "bounds"
fileprivate let cellIdentifier = "EasyPagingViewPageCell"

// MARK: - KVO
let PageCollectionViewKVOContext = UnsafeMutableRawPointer(bitPattern: 1)
let ContentViewKVOContext = UnsafeMutableRawPointer(bitPattern: 2)

public protocol EasyPagingViewPageViewDelegate: NSObjectProtocol {
    var pageView: UIView { get }
    var pageScrollView: UIScrollView { get }
}

public protocol EasyPagingViewDataSource: NSObjectProtocol {
    
    func numberOfLists(in easyPagingView: EasyPagingView) -> Int
    func easyPagingView(_ easyContainerScrollView: EasyPagingView, pageForItemAt index: Int) -> EasyPagingViewPageViewDelegate
}

open class EasyPagingView: UIScrollView {
    
    private enum ScrollingDirection {
        case up
        case down
    }
    
    public var defaultSelectedIndex: Int = 0
    public weak var dataSource: EasyPagingViewDataSource?
    public var pageHeaderView: UIView?
    public var pagePinView: UIView?
    public var pageCollectionView: UICollectionView!
    
    var pageDict = [Int : EasyPagingViewPageViewDelegate]()
    var pageCurrentOffsetDict = [Int: CGFloat]()
    var contentOffsetDict = [Int: CGFloat]()
    var pageCollectionViewPinY: CGFloat = 0
    
    /// 当 pinView 未到达最高点时切换列表
    var switchToNewPageWhenPinViewNotInTop: Bool = false
    var switchToNewPageWhenPinViewNotInTopContentOffset: CGFloat = 0
    var lastOffsetY: CGFloat = 0
    var isScrollingDown: Bool = false
    var pinViewOriginY: CGFloat = 0
    
    // 拖动
    var pageCollectionViewOriginY: CGFloat = 0
    var pinViewDragingBeginOriginY: CGFloat = 0
    var isPinViewDraging: Bool = false
    var panGesture: UIPanGestureRecognizer?
    
    var currentIndex: Int = 0
    var subviewsInLayoutOrder = [UIView]()
    var currentPageScrollView: UIScrollView?
    
    public var contentView: UIView!
    // 子视图之间距离
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInitForEasyContainerScrollview()
    }
    
    public var spacing: CGFloat = 0.0 {
        didSet {
            self.setNeedsLayout()
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func commonInitForEasyContainerScrollview() {
        
        contentView = EasyContainerScrollViewContentView()
        self.addSubview(contentView)
        
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.scrollDirection = .horizontal
        pageCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        pageCollectionView.dataSource = self
        pageCollectionView.delegate = self
        pageCollectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellIdentifier)
        pageCollectionView.isPagingEnabled = true
        pageCollectionView.bounces = false
        pageCollectionView.showsHorizontalScrollIndicator = false
        pageCollectionView.contentInsetAdjustmentBehavior = .never
        
        self.addObserver(self, forKeyPath: kContentOffset, options: .old, context: ContentViewKVOContext)
    }
    
    func reloadData() {
        
        if let headerView = pageHeaderView {
            contentView.addSubview(headerView)
        }
        
        if let pinView = pagePinView {
            panGesture = UIPanGestureRecognizer(target: self, action: #selector(pinViewPanGesture(_:)))
            pinView.addGestureRecognizer(panGesture!)
            contentView.addSubview(pinView)
        }
        
        contentView.addSubview(pageCollectionView)
        pageCollectionView.reloadData()
        if let pinView = pagePinView {
            contentView.bringSubviewToFront(pinView)
        }
    }
    
    // MARK: - Adding and removing subviews
    
    func didAddSubviewToContainer(_ subview: UIView) {
        
        let index = subviewsInLayoutOrder.firstIndex { subview === $0 }
        if let index = index {
            subviewsInLayoutOrder.remove(at: index)
            subviewsInLayoutOrder.append(subview)
            self.setNeedsLayout()
            return
        }
        
        subviewsInLayoutOrder.append(subview)
        
        if let scrollView = subview as? UIScrollView{
            if scrollView !== pageCollectionView {
                scrollView.isScrollEnabled = false
            }
            scrollView.addObserver(self, forKeyPath: kContentSize, options: .old, context: PageCollectionViewKVOContext)
        } else {
            subview.addObserver(self, forKeyPath: kFrame, options: .old, context: PageCollectionViewKVOContext)
            subview.addObserver(self, forKeyPath: kBounds, options: .old, context: PageCollectionViewKVOContext)
        }
        
        self.setNeedsLayout()
        
    }
    
    func willRemoveSubviewFromContainer(_ subview: UIView) {
        if let scrollView = subview as? UIScrollView{
            scrollView.isScrollEnabled = false
            scrollView.removeObserver(self, forKeyPath: kContentSize, context: PageCollectionViewKVOContext)
        } else {
            subview.removeObserver(self, forKeyPath: kFrame, context: PageCollectionViewKVOContext)
            subview.removeObserver(self, forKeyPath: kBounds, context: PageCollectionViewKVOContext)
        }
        
        subviewsInLayoutOrder.removeAll(where: { $0 === subview })
        self.setNeedsLayout()
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        guard !isPinViewDraging else { return }
        
        
        
        var pageScrollViewOffsetY: CGFloat = 0
        var switchToNewPageAndScrollDownOffsetY: CGFloat = 0
        if switchToNewPageWhenPinViewNotInTop {
            if isScrollingDown {
                // 向下滚动
                switchToNewPageAndScrollDownOffsetY = self.contentOffset.y - switchToNewPageWhenPinViewNotInTopContentOffset
                self.contentOffset.y = switchToNewPageWhenPinViewNotInTopContentOffset
            }
            
            if !isPinViewScrollToTop {
                pageScrollViewOffsetY = pageCurrentOffsetDict[currentIndex] ?? 0
                pageScrollViewOffsetY += switchToNewPageAndScrollDownOffsetY
                
                let contentOffsetY = contentOffsetDict[currentIndex] ?? 0
                contentOffsetDict[currentIndex] = contentOffsetY + switchToNewPageAndScrollDownOffsetY
                if pageScrollViewOffsetY <= 0 {
                    switchToNewPageWhenPinViewNotInTop = false
                    pageScrollViewOffsetY = 0
                }
            } else {
                switchToNewPageWhenPinViewNotInTop = false
                self.contentOffset.y += (pageCurrentOffsetDict[currentIndex] ?? 0)
            }
            switchToNewPageWhenPinViewNotInTopContentOffset = self.contentOffset.y
        } else {
            contentOffsetDict[currentIndex] = self.contentOffset.y
        }
        
        contentView.frame = self.bounds
        contentView.bounds = CGRect(origin: self.contentOffset, size: contentView.bounds.size)
        let pagePinViewHeight: CGFloat = pagePinView?.frame.height ?? 0
        pageCollectionView.frame.size.height = self.bounds.height - pagePinViewHeight
        var yOffsetOfCurrentSubview: CGFloat = 0.0
        
        for index in 0..<subviewsInLayoutOrder.count {
            let subview = subviewsInLayoutOrder[index]
            
            if subview === pageCollectionView {
                self.pageCollectionViewPinY = yOffsetOfCurrentSubview - pagePinViewHeight
                var frame = subview.frame
                frame.origin.y = max(yOffsetOfCurrentSubview, self.contentOffset.y + pagePinViewHeight)
                frame.origin.x = 0
                frame.size.width = self.contentView.bounds.width
                subview.frame = frame
                pageCollectionViewOriginY = frame.origin.y
                if let pageView = pageDict[currentIndex]?.pageScrollView {
                    if !isPinViewScrollToTop {
                        pageView.contentOffset.y = pageScrollViewOffsetY
                        pageCurrentOffsetDict[currentIndex] = pageScrollViewOffsetY
                    } else {
                        let pageOffsetY = self.contentOffset.y - pageCollectionViewPinY
                        pageView.contentOffset.y = pageOffsetY
                        pageCurrentOffsetDict[currentIndex] = pageOffsetY
                    }
                    yOffsetOfCurrentSubview += pageView.contentSize.height
                }

            } else if let scrollView = subview as? UIScrollView {
                var frame = subview.frame
                var contentOffset = scrollView.contentOffset
                
                if self.contentOffset.y < yOffsetOfCurrentSubview {
                    contentOffset.y = 0.0
                    frame.origin.y = yOffsetOfCurrentSubview
                } else {
                    contentOffset.y = self.contentOffset.y - yOffsetOfCurrentSubview
                    frame.origin.y = self.contentOffset.y
                }
                
                let remainingBoundsHeight = max(self.bounds.maxY, frame.minY)
                let remainingContentHeight = max(scrollView.contentSize.height - contentOffset.y, 0.0)
                frame.size.height = min(remainingBoundsHeight, remainingContentHeight)
                frame.size.width = self.contentView.bounds.width
                
                subview.frame = frame
                scrollView.contentOffset = contentOffset
                
                yOffsetOfCurrentSubview += scrollView.contentSize.height + scrollView.contentInset.top + scrollView.contentInset.bottom
            }  else {
                var frame = subview.frame
                var originY: CGFloat = 0
                if contentOffset.y < yOffsetOfCurrentSubview - (bounds.height - frame.height) {
                    originY = contentOffset.y + bounds.height - frame.height
                    panGesture?.isEnabled = true
                } else {
                    panGesture?.isEnabled = false
                    originY = max(yOffsetOfCurrentSubview, self.contentOffset.y)
                }
                frame.origin.y = max(originY, self.contentOffset.y)
                frame.origin.x = 0
                frame.size.width = self.contentView.bounds.width
                subview.frame = frame
                self.pinViewOriginY = originY
                yOffsetOfCurrentSubview += frame.size.height
            }
            
            if index < subviewsInLayoutOrder.count - 1 {
                yOffsetOfCurrentSubview += self.spacing
            }
        }
        
        let minimumContentHeight = self.bounds.size.height - (self.contentInset.top + self.contentInset.bottom)
        let initialContentOffset = self.contentOffset
        self.contentSize = CGSize(width: self.bounds.width, height: max(yOffsetOfCurrentSubview, minimumContentHeight))
        
        if initialContentOffset != self.contentOffset {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }
    
    var isPinViewScrollToTop: Bool {
        return self.contentOffset.y > self.pageCollectionViewPinY
    }
    
    // TODO: 切换 page 的 scrollView contentOffset.y
    func horizontalScrollDidEnd(at index: Int) {
        
        let currentContentOffsetY = contentOffsetDict[index] ?? 0
        if self.contentOffset.y > self.pageCollectionViewPinY {
            // pinView 已经达到顶部，直接切换 contentOffsetY
            self.contentOffset.y = max(self.pageCollectionViewPinY, currentContentOffsetY)
        } else {
//            self.contentOffset.y = max(contentOffset.y, currentContentOffsetY)
            // 如果 currentContentOffsetY 不为 nil
            // 当向上滚动，整个 ScrollView 向上，直到 contentOffset.y 达到 pageCollectionViewPinY
            // 当向下滚动，当前page向下，直到 page.contentOffset.y 到达 0.
            // pinView 未滚动到顶部，需要情况切换 contentOffsetY，在 layoutSubviews() 内切换。
            if currentIndex != index {
                switchToNewPageWhenPinViewNotInTop = true
                switchToNewPageWhenPinViewNotInTopContentOffset = contentOffset.y
            }
        }
        currentIndex = index
    }

    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if context == PageCollectionViewKVOContext {
            
            if keyPath == kContentSize {
                if let scrollView = object as? UIScrollView {
                    let oldContentSize = change?[.oldKey] as! CGSize
                    let newContentSize = scrollView.contentSize
                    if oldContentSize != newContentSize && scrollView === pageDict[currentIndex]?.pageScrollView {
                        self.setNeedsLayout()
                        self.layoutIfNeeded()
                    }
                }
            } else if keyPath == kFrame || keyPath == kBounds {
                if let subview = object as? UIView {
                    let oldFrame = change?[.oldKey] as! CGRect
                    let newFrame = subview.frame
                    if oldFrame != newFrame {
                        self.setNeedsLayout()
                        self.layoutIfNeeded()
                    }
                }
            }
        } else if context == ContentViewKVOContext {
            if keyPath == kContentOffset {
                if let scrollView = object as? UIScrollView {
                    if scrollView.contentOffset.y < lastOffsetY {
                        isScrollingDown = true
                    } else {
                        isScrollingDown = false
                    }
                    lastOffsetY = scrollView.contentOffset.y
                    
                    let didEndScroll = scrollView.isTracking && !scrollView.isDragging && !scrollView.isDecelerating
                    if !didEndScroll {
                        panGesture?.isEnabled = false
                    }
                }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
}

// MARK: - CollectionView DataSource & DelegateFlowLayout
extension EasyPagingView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return pageCollectionView.bounds.size
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataSource?.numberOfLists(in: self) ?? 0
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellIdentifier, for: indexPath)
        var page = pageDict[indexPath.item]
        if page == nil {
            page = dataSource?.easyPagingView(self, pageForItemAt: indexPath.item)
            pageDict[indexPath.item] = page!
            page?.pageView.setNeedsLayout()
            page?.pageView.layoutIfNeeded()
            
            page?.pageScrollView.addObserver(self, forKeyPath: kContentSize, options: .old, context: PageCollectionViewKVOContext)
            
        }
        
        if let pageView = page?.pageView, pageView.superview != cell.contentView {
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            pageView.frame = cell.contentView.bounds
            cell.contentView.addSubview(pageView)
            page?.pageScrollView.frame = cell.contentView.bounds
        }
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        
        
        let page = pageDict[indexPath.item]
        page?.pageScrollView.contentOffset.y = pageCurrentOffsetDict[indexPath.item] ?? 0
        
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let index = Int(scrollView.contentOffset.x/scrollView.bounds.size.width)
        horizontalScrollDidEnd(at: index)
    }
    
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            let index = Int(scrollView.contentOffset.x/scrollView.bounds.size.width)
            horizontalScrollDidEnd(at: index)
        }
    }
}

extension EasyPagingView {
    @objc func pinViewPanGesture(_ gesture: UIPanGestureRecognizer) {
        
        if gesture.state == .began {
            if !isPinViewDraging {
                self.isScrollEnabled = false
                isPinViewDraging = true
                pageDict[currentIndex]?.pageScrollView.isScrollEnabled = true
            }
            pinViewDragingBeginOriginY = pagePinView!.frame.origin.y
            
        } else if gesture.state == .changed {
            let gestureOffsetY = gesture.translation(in: contentView).y
            pagePinView?.frame.origin.y = (pinViewDragingBeginOriginY + gestureOffsetY)
            pageCollectionView.frame.origin.y = (pagePinView!.frame.origin.y + pagePinView!.frame.height)
        } else if gesture.state == .ended {
            let velocityY = gesture.velocity(in: contentView).y
            let gestureOffsetY = gesture.translation(in: contentView).y
            let panHeight = (bounds.height - pagePinView!.frame.height) / 2
            let pinViewShouldScrollToBottom: Bool
            if gestureOffsetY < 0 {
                // 向上滚动
                if -gestureOffsetY > panHeight || velocityY < -300 {
                    pinViewShouldScrollToBottom = false
                } else {
                    pinViewShouldScrollToBottom = true
                }
            } else {
                // 向下滚动
                if gestureOffsetY > panHeight || velocityY > 300 {
                    pinViewShouldScrollToBottom = true
                } else {
                    pinViewShouldScrollToBottom = false
                }
            }
            
            let pinViewDragingEndOriginY = !pinViewShouldScrollToBottom ? pinViewOriginY - bounds.height + pagePinView!.frame.height : pinViewOriginY
            UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
                self.pagePinView?.frame.origin.y = pinViewDragingEndOriginY
                self.pageCollectionView.frame.origin.y = (self.pagePinView!.frame.origin.y + self.pagePinView!.frame.height)
            } completion: { (success) in
                if success {
                    if pinViewDragingEndOriginY == self.pinViewOriginY {
                        self.isPinViewDraging = false
                        self.pageCollectionView.frame.origin.y = self.pageCollectionViewOriginY
                        self.pageDict[self.currentIndex]?.pageScrollView.isScrollEnabled = false
                        self.isScrollEnabled = true
                    }
                }
            }
        }
    }
}
