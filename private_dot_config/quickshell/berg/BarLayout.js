function collisionAwareX(containerWidth, itemWidth, leftBoundary, rightBoundary) {
    const centered = (containerWidth - itemWidth) / 2;
    const rightLimited = Math.min(centered, rightBoundary - itemWidth);

    // If the three groups cannot all fit, preserve the right-side boundary;
    // otherwise keep the clock clear of both edge groups.
    return leftBoundary <= rightBoundary - itemWidth
        ? Math.max(leftBoundary, rightLimited)
        : rightLimited;
}
