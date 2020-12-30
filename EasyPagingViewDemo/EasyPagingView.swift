//
//  EasyContainerScrollView.swift
//  ScrollViewDemo
//
//  Created by quanhua on 2020/12/20.
//

import UIKit

// 参考: https://oleb.net/blog/2014/05/scrollviews-inside-scrollviews/

fileprivate let kContentSize = "contentSize"
fileprivate let kFrame = "frame"
fileprivate let kBounds = "bounds"

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
    
    let cellIdentifier = "EasyPagingViewPageCell"
    var pageDict = [Int : EasyPagingViewPageViewDelegate]()
    var pageCurrentOffsetDict = [Int: CGFloat]()
    var contentOffsetDict = [Int: CGFloat]()
    var pageCollectionViewOriginY: CGFloat = 0
    var isNewPage: Bool = false
    var lastOffsetY: CGFloat = 0
    var isUp: Bool = false

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
        
        self.delegate = self
    }
    
    func reloadData() {
        
        if let headerView = pageHeaderView {
            contentView.addSubview(headerView)
        }
        
        if let pinView = pagePinView {
            contentView.addSubview(pinView)
        }
        
        contentView.addSubview(pageCollectionView)
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
            scrollView.addObserver(self, forKeyPath: kContentSize, options: .old, context: KVOContext)
        } else {
            subview.addObserver(self, forKeyPath: kFrame, options: .old, context: KVOContext)
            subview.addObserver(self, forKeyPath: kBounds, options: .old, context: KVOContext)
        }
        
        self.setNeedsLayout()
        
    }
    
    func willRemoveSubviewFromContainer(_ subview: UIView) {
        if let scrollView = subview as? UIScrollView{
            scrollView.isScrollEnabled = false
            scrollView.removeObserver(self, forKeyPath: kContentSize, context: KVOContext)
        } else {
            subview.removeObserver(self, forKeyPath: kFrame, context: KVOContext)
            subview.removeObserver(self, forKeyPath: kBounds, context: KVOContext)
        }
        
        subviewsInLayoutOrder.removeAll(where: { $0 === subview })
        self.setNeedsLayout()
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        var aa: CGFloat = 0
        if isNewPage {
            print("isUp: \(isUp)")
            if !isUp {
                aa = self.contentOffset.y - (contentOffsetDict[currentIndex] ?? 0)
                self.contentOffset.y = (contentOffsetDict[currentIndex] ?? 0)
            }
        }
        
        contentView.frame = self.bounds
        contentView.bounds = CGRect(origin: self.contentOffset, size: contentView.bounds.size)
        let pagePinViewHeight: CGFloat = pagePinView?.frame.height ?? 0
        pageCollectionView.frame.size.height = self.bounds.height - pagePinViewHeight
        var yOffsetOfCurrentSubview: CGFloat = 0.0
        
        for index in 0..<subviewsInLayoutOrder.count {
            let subview = subviewsInLayoutOrder[index]
            
            self.pageCollectionViewOriginY = yOffsetOfCurrentSubview - pagePinViewHeight
            if subview === pageCollectionView {
                var frame = subview.frame
                frame.origin.y = max(yOffsetOfCurrentSubview, self.contentOffset.y + pagePinViewHeight)
                frame.origin.x = 0
                frame.size.width = self.contentView.bounds.width
                subview.frame = frame
                if let pageView = pageDict[currentIndex]?.pageScrollView {
                    if self.contentOffset.y + pagePinViewHeight < yOffsetOfCurrentSubview {
                        
                        var pageOffsetY: CGFloat = 0
                        
                        if isNewPage {
                            pageOffsetY = pageCurrentOffsetDict[currentIndex] ?? 0
                            pageOffsetY += aa
                            if pageOffsetY <= 0 {
                                isNewPage = false
                                pageOffsetY = 0
                                aa = 0
                            }
                        }
                        pageView.contentOffset.y = pageOffsetY
                        pageCurrentOffsetDict[currentIndex] = pageOffsetY
                    } else {
                        if isNewPage {
                            isNewPage = false
                            self.contentOffset.y += (pageCurrentOffsetDict[currentIndex] ?? 0)
                            contentView.bounds.origin = self.contentOffset
                        }
                        let pageOffsetY = self.contentOffset.y + pagePinViewHeight - yOffsetOfCurrentSubview
                        pageView.contentOffset.y = pageOffsetY
                        pageCurrentOffsetDict[currentIndex] = pageOffsetY
                        print("pageOffsetY: \(pageOffsetY)")
                    }
                    contentOffsetDict[currentIndex] = self.contentOffset.y
                    print("contentOffset: \(self.contentOffset.y)")
                    yOffsetOfCurrentSubview += pageView.contentSize.height
                }

            } else if let scrollView = subview as? UIScrollView {
                var frame = subview.frame
                var contentOffset = scrollView.contentOffset
                
                if self.contentOffset.y < yOffsetOfCurrentSubview {
                    // 当前 scrollView 未滚动到顶部
                    contentOffset.y = 0.0
                    frame.origin.y = yOffsetOfCurrentSubview // 不断改变 scrollView 在 contentView 的位置(frame.originY)
                } else {
                    // 当前 scrollView 已滚动到顶部
                    // 固定 scrollView 在 contentView 的位置(frame.originY)
                    // 改变 scrollView 的 contentOffsetY
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
                frame.origin.y = max(yOffsetOfCurrentSubview, self.contentOffset.y)
                frame.origin.x = 0
                frame.size.width = self.contentView.bounds.width
                subview.frame = frame
                
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
    
    // TODO: 切换 page 的 scrollView contentOffset.y
    func horizontalScrollDidEnd(at index: Int) {
        
        let currentContentOffsetY = contentOffsetDict[index] ?? 0
        if self.contentOffset.y > self.pageCollectionViewOriginY {
            // pinView 已经达到顶部，直接切换 contentOffsetY
            self.contentOffset.y = max(self.pageCollectionViewOriginY, currentContentOffsetY)
        } else {
//            self.contentOffset.y = max(contentOffset.y, currentContentOffsetY)
            // 如果 currentContentOffsetY 不为 nil
            // 当向上滚动，整个 ScrollView 向上，直到 contentOffset.y 达到 pageCollectionViewOriginY
            // 当向下滚动，当前page向下，直到 page.contentOffset.y 到达 0.
            // pinView 未滚动到顶部，需要情况切换 contentOffsetY，在 layoutSubviews() 内切换。
            if currentIndex != index {
                isNewPage = true
                for i in 0..<dataSource!.numberOfLists(in: self) {
                    contentOffsetDict[i] = self.contentOffset.y
                }
            }
        }
        currentIndex = index
    }
    
    // MARK: - KVO
    let KVOContext = UnsafeMutableRawPointer(bitPattern: 1)

    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if context == KVOContext {
            
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
            
            page?.pageScrollView.addObserver(self, forKeyPath: kContentSize, options: .old, context: KVOContext)
            
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
        guard scrollView !== self else { return }
        let index = Int(scrollView.contentOffset.x/scrollView.bounds.size.width)
        horizontalScrollDidEnd(at: index)
    }
    
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView !== self else { return }
        if !decelerate {
            let index = Int(scrollView.contentOffset.x/scrollView.bounds.size.width)
            horizontalScrollDidEnd(at: index)
        }
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView ===  self {
            if scrollView.contentOffset.y > lastOffsetY {
                isUp = true
            } else {
                isUp = false
            }
            lastOffsetY = scrollView.contentOffset.y
        }
    }
}
