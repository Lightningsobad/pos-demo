function assertRange(value, min, max, label, inclusiveMin = true) {
  const validMin = inclusiveMin ? value >= min : value > min;
  if (!Number.isFinite(value) || !validMin || value > max) {
    throw new RangeError(`${label} must be a finite number in ${inclusiveMin ? '[' : '('}${min}, ${max}]`);
  }
}

/**
 * Calculate line-level discounts/VAT and order-level totals with per-step VND rounding.
 * @param {Array<object>} items
 * @param {number} [orderDiscountPercent=0]
 */
export function calculateOrderPricing(items, orderDiscountPercent = 0) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new RangeError('items must be a non-empty array');
  }
  assertRange(orderDiscountPercent, 0, 100, 'orderDiscountPercent');

  let subtotal = 0;
  const computedItems = items.map((item, index) => {
    const quantity = item.quantity;
    const unitPrice = item.unitPrice;
    const discountPercent = item.discountPercent ?? 0;
    const vatRate = item.vatRate ?? 0;

    assertRange(quantity, 0, Number.MAX_SAFE_INTEGER, `items[${index}].quantity`, false);
    assertRange(unitPrice, 0, Number.MAX_SAFE_INTEGER, `items[${index}].unitPrice`);
    assertRange(discountPercent, 0, 100, `items[${index}].discountPercent`);
    assertRange(vatRate, 0, 100, `items[${index}].vatRate`);

    const grossAmount = unitPrice * quantity;
    const discountAmount = Math.round(grossAmount * (discountPercent / 100));
    const taxableAmount = grossAmount - discountAmount;
    const vatAmount = Math.round(taxableAmount * (vatRate / 100));
    const lineTotal = taxableAmount + vatAmount;
    subtotal += lineTotal;

    return {
      productId: item.productId,
      sku: item.sku,
      name: item.name,
      unit: item.unit,
      unitPrice,
      quantity,
      discountPercent,
      discountAmount,
      vatRate,
      vatAmount,
      lineTotal,
      note: item.note ?? null,
    };
  });

  const discountAmount = Math.round(subtotal * (orderDiscountPercent / 100));
  const totalPayable = subtotal - discountAmount;

  return {
    items: computedItems,
    subtotal,
    discountPercent: orderDiscountPercent,
    discountAmount,
    totalPayable,
  };
}
