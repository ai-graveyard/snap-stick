import { useState, useEffect, useCallback } from "react";
import { PhotoRecord } from "@/types";

const DB_NAME = "pai-li-tie-db";
const STORE_NAME = "photos";

function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: "id" });
      }
    };
  });
}

export function usePhotoHistory() {
  const [photos, setPhotos] = useState<PhotoRecord[]>([]);

  // 从 IndexedDB 加载历史
  useEffect(() => {
    async function load() {
      try {
        const db = await openDB();
        const tx = db.transaction(STORE_NAME, "readonly");
        const store = tx.objectStore(STORE_NAME);
        const all = await new Promise<PhotoRecord[]>((resolve, reject) => {
          const req = store.getAll();
          req.onsuccess = () => resolve(req.result);
          req.onerror = () => reject(req.error);
        });
        // 旧记录缺 paperStyleID 时兜底为默认相纸
        for (const p of all) {
          if (!p.paperStyleID) p.paperStyleID = "cream";
        }
        // 按时间倒序
        all.sort((a, b) => b.timestamp - a.timestamp);
        setPhotos(all);
      } catch (err) {
        console.error("加载历史失败:", err);
      }
    }
    load();
  }, []);

  const addPhoto = useCallback(async (photo: PhotoRecord) => {
    try {
      const db = await openDB();
      const tx = db.transaction(STORE_NAME, "readwrite");
      const store = tx.objectStore(STORE_NAME);
      store.put(photo);
      await new Promise<void>((resolve, reject) => {
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
      });
      setPhotos((prev) => [photo, ...prev]);
    } catch (err) {
      console.error("保存照片失败:", err);
    }
  }, []);

  const clearPhotos = useCallback(async () => {
    try {
      const db = await openDB();
      const tx = db.transaction(STORE_NAME, "readwrite");
      const store = tx.objectStore(STORE_NAME);
      store.clear();
      await new Promise<void>((resolve, reject) => {
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
      });
      setPhotos([]);
    } catch (err) {
      console.error("清空记录失败:", err);
    }
  }, []);

  const setPaperStyle = useCallback(async (id: string, styleID: string) => {
    try {
      const db = await openDB();
      const tx = db.transaction(STORE_NAME, "readwrite");
      const store = tx.objectStore(STORE_NAME);
      const existing = await new Promise<PhotoRecord | undefined>((resolve, reject) => {
        const req = store.get(id);
        req.onsuccess = () => resolve(req.result as PhotoRecord | undefined);
        req.onerror = () => reject(req.error);
      });
      if (existing) store.put({ ...existing, paperStyleID: styleID });
      await new Promise<void>((resolve, reject) => {
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
      });
      setPhotos((prev) =>
        prev.map((p) => (p.id === id ? { ...p, paperStyleID: styleID } : p))
      );
    } catch (err) {
      console.error("更新相纸失败:", err);
    }
  }, []);

  const deletePhoto = useCallback(async (id: string) => {
    try {
      const db = await openDB();
      const tx = db.transaction(STORE_NAME, "readwrite");
      const store = tx.objectStore(STORE_NAME);
      store.delete(id);
      await new Promise<void>((resolve, reject) => {
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
      });
      setPhotos((prev) => prev.filter((photo) => photo.id !== id));
    } catch (err) {
      console.error("删除照片失败:", err);
    }
  }, []);

  return { photos, addPhoto, clearPhotos, deletePhoto, setPaperStyle };
}
