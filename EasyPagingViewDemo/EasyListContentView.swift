//
//  EasyListContentView.swift
//  ScrollViewDemo
//
//  Created by Quanhua Peng on 2020/12/26.
//

import UIKit

class EasyListContentView: UIView {

    var tableView: UITableView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        tableView = UITableView(frame: frame, style: .plain)
        tableView.dataSource = self
        tableView.rowHeight = 100
        tableView.isScrollEnabled = false
        addSubview(tableView)
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

extension EasyListContentView: EasyPagingViewPageViewDelegate {
    var pageView: UIView {
        return self
    }
    
    var pageScrollView: UIScrollView {
        return tableView
    }
}

extension EasyListContentView: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 30
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        var cell = tableView.dequeueReusableCell(withIdentifier: "cell")
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: "cell")
        }
        cell?.textLabel?.text = "\(indexPath.row)"
        cell?.backgroundColor = .clear
        return cell!
    }
    
    
}
