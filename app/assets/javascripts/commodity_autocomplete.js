/**
 * Commodity Autocomplete Functionality
 * Handles autocompletion for commodity remapping inputs
 */

class CommodityAutocomplete {
  constructor() {
    this.searchDelay = 300; // ms
    this.minSearchLength = 2;
    this.activeDropdowns = new Map();
    
    this.init();
  }
  
  init() {
    // Initialize autocomplete for existing inputs
    document.querySelectorAll('[data-commodity-autocomplete]').forEach(input => {
      this.setupAutocomplete(input);
    });
    
    // Handle dynamically added inputs (if needed)
    document.addEventListener('DOMContentLoaded', () => {
      this.initializeAll();
    });
  }
  
  initializeAll() {
    document.querySelectorAll('[data-commodity-autocomplete]').forEach(input => {
      if (!input.hasAttribute('data-autocomplete-initialized')) {
        this.setupAutocomplete(input);
      }
    });
  }
  
  setupAutocomplete(input) {
    input.setAttribute('data-autocomplete-initialized', 'true');
    
    // Create dropdown container
    const dropdown = this.createDropdown(input);
    
    let searchTimeout;
    
    // Handle input events
    input.addEventListener('input', (e) => {
      const query = e.target.value.trim();
      
      clearTimeout(searchTimeout);
      
      if (query.length >= this.minSearchLength) {
        searchTimeout = setTimeout(() => {
          this.search(query, input, dropdown);
        }, this.searchDelay);
      } else {
        this.hideDropdown(dropdown);
      }
    });
    
    // Handle focus/blur events
    input.addEventListener('focus', (e) => {
      if (e.target.value.length >= this.minSearchLength) {
        this.search(e.target.value.trim(), input, dropdown);
      }
    });
    
    input.addEventListener('blur', (e) => {
      // Delay hiding to allow for clicks on dropdown items
      setTimeout(() => {
        this.hideDropdown(dropdown);
      }, 200);
    });
    
    // Handle keyboard navigation
    input.addEventListener('keydown', (e) => {
      this.handleKeyboard(e, dropdown);
    });
  }
  
  createDropdown(input) {
    const dropdown = document.createElement('div');
    dropdown.className = 'commodity-autocomplete-dropdown';
    dropdown.style.cssText = `
      position: absolute;
      top: 100%;
      left: 0;
      right: 0;
      background: white;
      border: 1px solid #d1d5db;
      border-top: none;
      border-radius: 0 0 6px 6px;
      max-height: 200px;
      overflow-y: auto;
      z-index: 1000;
      display: none;
      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
    `;
    
    // Position relative to input
    const container = input.parentElement;
    container.style.position = 'relative';
    container.appendChild(dropdown);
    
    return dropdown;
  }
  
  async search(query, input, dropdown) {
    try {
      const response = await fetch(`/commodity_references/search?q=${encodeURIComponent(query)}`);
      
      if (!response.ok) {
        throw new Error('Search failed');
      }
      
      const results = await response.json();
      this.displayResults(results, input, dropdown);
      
    } catch (error) {
      console.error('Commodity search error:', error);
      this.hideDropdown(dropdown);
    }
  }
  
  displayResults(results, input, dropdown) {
    if (results.length === 0) {
      dropdown.innerHTML = '<div class="p-3 text-sm text-gray-500">No matches found</div>';
      this.showDropdown(dropdown);
      return;
    }
    
    dropdown.innerHTML = '';
    
    results.forEach((item, index) => {
      const option = document.createElement('div');
      option.className = 'commodity-option';
      option.style.cssText = `
        padding: 8px 12px;
        cursor: pointer;
        border-bottom: 1px solid #f3f4f6;
        font-size: 14px;
      `;
      
      // Color code by scope status
      const scopeColor = item.scope === 'In Scope' ? 'text-green-700' : 'text-red-700';
      
      option.innerHTML = `
        <div class="font-medium text-gray-900">${this.highlightMatch(item.text, input.value)}</div>
        <div class="text-xs ${scopeColor}">${item.scope || 'No scope'}</div>
      `;
      
      // Handle hover
      option.addEventListener('mouseenter', () => {
        this.clearHighlight(dropdown);
        option.style.backgroundColor = '#f3f4f6';
        option.setAttribute('data-highlighted', 'true');
      });
      
      option.addEventListener('mouseleave', () => {
        option.style.backgroundColor = '';
        option.removeAttribute('data-highlighted');
      });
      
      // Handle click
      option.addEventListener('click', () => {
        this.selectOption(item, input, dropdown);
      });
      
      dropdown.appendChild(option);
    });
    
    this.showDropdown(dropdown);
  }
  
  highlightMatch(text, query) {
    const regex = new RegExp(`(${query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi');
    return text.replace(regex, '<strong>$1</strong>');
  }
  
  selectOption(item, input, dropdown) {
    input.value = item.text;
    input.setAttribute('data-selected-id', item.id);
    
    // Update scope indicator if exists
    const itemId = input.getAttribute('data-item-id');
    if (itemId) {
      this.updateScopeIndicator(itemId, item.scope);
    }
    
    // Mark as changed for styling
    input.style.backgroundColor = '#fef3c7';
    
    this.hideDropdown(dropdown);
    
    // Trigger change event for any listening code
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }
  
  updateScopeIndicator(itemId, scope) {
    const indicator = document.getElementById(`scope-${itemId}`);
    if (indicator) {
      const colorClass = scope === 'In Scope' ? 'text-green-700 bg-green-50' : 'text-red-700 bg-red-50';
      indicator.innerHTML = `<span class="inline-flex px-2 py-1 text-xs font-medium rounded ${colorClass}">${scope}</span>`;
    }
  }
  
  handleKeyboard(e, dropdown) {
    const options = dropdown.querySelectorAll('.commodity-option');
    const highlighted = dropdown.querySelector('[data-highlighted="true"]');
    
    switch(e.key) {
      case 'ArrowDown':
        e.preventDefault();
        this.highlightNext(options, highlighted);
        break;
        
      case 'ArrowUp':
        e.preventDefault();
        this.highlightPrevious(options, highlighted);
        break;
        
      case 'Enter':
        e.preventDefault();
        if (highlighted) {
          highlighted.click();
        }
        break;
        
      case 'Escape':
        this.hideDropdown(dropdown);
        break;
    }
  }
  
  highlightNext(options, current) {
    this.clearHighlight(options[0].parentElement);
    
    if (!current) {
      if (options[0]) {
        this.highlight(options[0]);
      }
    } else {
      const currentIndex = Array.from(options).indexOf(current);
      const nextIndex = (currentIndex + 1) % options.length;
      this.highlight(options[nextIndex]);
    }
  }
  
  highlightPrevious(options, current) {
    this.clearHighlight(options[0].parentElement);
    
    if (!current) {
      if (options[options.length - 1]) {
        this.highlight(options[options.length - 1]);
      }
    } else {
      const currentIndex = Array.from(options).indexOf(current);
      const prevIndex = currentIndex === 0 ? options.length - 1 : currentIndex - 1;
      this.highlight(options[prevIndex]);
    }
  }
  
  highlight(option) {
    option.style.backgroundColor = '#f3f4f6';
    option.setAttribute('data-highlighted', 'true');
  }
  
  clearHighlight(dropdown) {
    dropdown.querySelectorAll('[data-highlighted="true"]').forEach(option => {
      option.style.backgroundColor = '';
      option.removeAttribute('data-highlighted');
    });
  }
  
  showDropdown(dropdown) {
    dropdown.style.display = 'block';
  }
  
  hideDropdown(dropdown) {
    dropdown.style.display = 'none';
  }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.commodityAutocomplete = new CommodityAutocomplete();
});

// Also handle Turbo/AJAX page loads
document.addEventListener('turbo:load', () => {
  if (window.commodityAutocomplete) {
    window.commodityAutocomplete.initializeAll();
  }
});