package container_intrusive_list

import "base:intrinsics"
import "core:debug/trace"

insert_after :: proc "contextless" (list: ^List, current_node: ^Node, new_node: ^Node) {
    if new_node != nil && current_node != nil {
        new_node.prev = current_node
		new_node.next = current_node.next

        if current_node.next != nil {  
			current_node.next.prev = new_node
        } else {
            list.tail = new_node
        }
        current_node.next = new_node
    } else {
		panic_contextless("insert_after")
	}
}

insert_before :: proc "contextless" (list: ^List, current_node: ^Node, new_node: ^Node) {
    if new_node != nil && current_node != nil {
        new_node.next = current_node
		new_node.prev = current_node.prev

        if current_node.prev != nil {
			current_node.prev.next = new_node
        } else {
            list.head = new_node
        }
        current_node.prev = new_node
    } else {
		panic_contextless("insert_before")
	}
}