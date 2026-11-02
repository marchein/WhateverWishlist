export interface UserRow {
  id: string;
  email: string;
  display_name: string;
  password_hash: string;
  session_version: number;
  created_at: string;
}

export interface WishlistRow {
  id: string;
  owner_id: string;
  title: string;
  description: string | null;
  event_date: string | null;
  share_token: string;
  created_at: string;
  updated_at: string;
}

export interface ItemRow {
  id: string;
  wishlist_id: string;
  title: string;
  notes: string | null;
  image_url: string | null;
  price: number | null;
  currency: string | null;
  priority: number;
  quantity: number;
  links: string;
  created_at: string;
  updated_at: string;
}

export interface PurchaseRow {
  id: string;
  item_id: string;
  quantity: number;
  buyer_name: string;
  buyer_user_id: string | null;
  created_at: string;
  reverted_at: string | null;
  reverted_by_name: string | null;
  reverted_by_user_id: string | null;
}

export const toUserDto = (row: Pick<UserRow, 'id' | 'email' | 'display_name'>) => ({
  id: row.id,
  email: row.email,
  displayName: row.display_name,
});

export const toWishlistDto = (row: WishlistRow & { item_count?: number }) => ({
  id: row.id,
  title: row.title,
  description: row.description,
  eventDate: row.event_date,
  shareToken: row.share_token,
  itemCount: row.item_count,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

export const toItemDto = (row: ItemRow) => ({
  id: row.id,
  wishlistId: row.wishlist_id,
  title: row.title,
  notes: row.notes,
  imageUrl: row.image_url,
  price: row.price,
  currency: row.currency,
  priority: row.priority,
  quantity: row.quantity,
  links: JSON.parse(row.links) as string[],
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

export const toPurchaseDto = (row: PurchaseRow, viewerId: string | undefined) => ({
  id: row.id,
  quantity: row.quantity,
  buyerName: row.buyer_name,
  createdAt: row.created_at,
  revertedAt: row.reverted_at,
  revertedByName: row.reverted_by_name,
  isMine: viewerId !== undefined && row.buyer_user_id === viewerId,
});

export const activePurchasedQuantity = (purchases: PurchaseRow[]) =>
  purchases.filter((p) => !p.reverted_at).reduce((sum, p) => sum + p.quantity, 0);

export const now = () => new Date().toISOString();
